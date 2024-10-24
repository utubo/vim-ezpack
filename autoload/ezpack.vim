vim9script

g:ezpack_home = get(g:, 'ezpack_home', expand($'{&pp->split(',')[0]}/pack/ezpack'))

var plugins: list<any> = []
var results: list<any> = []

def MkParent(path: string): string
  const p = $'{path->substitute('[\/][^\/]*$', '', '')}'
  mkdir(p, 'p')
  return p
enddef

def GitPull(): list<any>
  const l = plugins->len()
  redraw
  echo $'Ezpack: (0/{l}) wait for install.'
  var job_count = 0
  results = []
  const current = getcwd()
  for p in plugins
    const s = p.opt || !!p.trigger ? ['opt', 'start'] : ['start', 'opt']
    const path = expand($'{g:ezpack_home}/{s[0]}/{p.name}')
    const extra = expand($'{g:ezpack_home}/{s[1]}/{p.name}')
    if isdirectory(extra) && !isdirectory(path)
      rename(extra, path)
    endif
    var r = add(results, {
      label: p.label,
      out: [],
      status: -1,
      cwd: path,
      gitcmd: 'git pull',
      path: path,
    })[-1]
    if !isdirectory(path)
      r.cwd = MkParent(path)
      r.gitcmd = $'git clone --depth=1 {p.url}'
    endif
    const ExitCb = (job, status) => {
      ++job_count
      r.status = isdirectory(path) ? status : -1
      redraw
      echo $'Ezpack: ({job_count}/{l}) {r.gitcmd->split(' ')[1]} {r.label}'
    }
    const OutCb = (ch, msg) => add(r.out, [msg])
    if has('win32')
      job_start(r.gitcmd, { cwd: r.cwd, exit_cb: ExitCb, out_cb: OutCb, err_cb: OutCb })
    else
      # too many jobs kill vim on sakura rental server.
      chdir(r.cwd)
      OutCb(0, [system(r.gitcmd)])
      ExitCb(0, v:shell_error)
    endif
  endfor
  chdir(current)
  while job_count < l
    sleep 50m
  endwhile
  var updated = []
  var cloned = []
  var errors = []
  for r in results
    r.out = r.out->flattennew()
    if r.status !=# 0 && r.status !=# 128
      errors += [r.path]
    elseif r.gitcmd ==# 'git pull'
      if r.out[0]->trim() !=# 'Already up to date.'
        updated += [r.path]
      endif
    else
      cloned += [r.path]
    endif
  endfor
  return [updated, cloned, errors]
enddef

# TODO: Is this unnecessary?
def ExecuteCloned(cloned: list<string>)
  &rtp = $'{cloned->join(',')},{&rtp}'
  for c in cloned
    for f in globpath($'{c}/plugins', '*.vim')
      execute 'source' f
    endfor
  endfor
enddef

def CreateAutocmd(): string
  var lines = ['vim9script', 'augroup ezpack', 'au!']
  for p in plugins
    if !p.trigger
      continue
    endif
    lines += [$"au ezpack {p.trigger} packadd {p.name}"]
  endfor
  lines += ['augroup END']
  const path = expand($'{g:ezpack_home}/start/_/plugin/_.vim')
  MkParent(path)
  writefile(lines, path)
  return path
enddef

# -----------------------
# Interface

export def Init()
  plugins = []
enddef

export def Ezpack(...fargs: list<any>)
  const opt = get(fargs, 1, '') ==# '<opt>'
  const trigger = fargs[(opt ? 2 : 1) : ]->join(' ')
  plugins += [{
    label: fargs[0],
    name: fargs[0]->matchstr('[^/]*$')->substitute('\.git$', '', ''),
    url: fargs[0] =~# '\.git$' ? fargs[0] : $'https://github.com/{fargs[0]}.git',
    opt: opt,
    trigger: trigger,
  }]
enddef

export def Install()
  if exists('#User#EzpackInstallPre')
    doautocmd User EzpackInstallPre
  endif
  const [updated, cloned, errors] = GitPull()
  const autoCmdPath = CreateAutocmd()
  ExecuteCloned(cloned)
  execute 'source' autoCmdPath
  redraw
  if !!errors
    echoe 'Ezpack: FAILED! see EzpackLog.'
  elseif !updated
    echo 'Ezpack: COMPLETED.'
  else
    echoh WarningMsg
    echom 'Ezpack: Some pulgins are updated, plz restart vim.'
    echoh Normal
  endif
  if has('vim_starting')
    feedkeys("\n")
  endif
enddef

export def CleanUp()
  if !plugins
    redraw
    echom 'Ezpack: The list of plugins is empty.'
    return
  endif
  var names = ['_']
  for p in plugins
    add(names, p.name)
  endfor
  const dirs =
    globpath($'{g:ezpack_home}/start', '*')->split("\n") +
    globpath($'{g:ezpack_home}/opt', '*')->split("\n")
  for f in dirs
    const name = matchstr(f, '[^\/]\+$')
    if index(names, name) !=# -1
      continue
    endif
    if !isdirectory($'{f}/plugin') && !isdirectory($'{f}/autoload')
      continue
    endif
    if input($'rm {f} (y/n): ') != 'y'
      continue
    endif
    delete(f, 'rf')
  endfor
  redraw
  echo 'Ezpack: COMPLETED.'
enddef

export def Log()
  for r in results
    echo r.label
    if r.status !=# 0 && r.status !=# 128
      echoh ErrorMsg
    else
      echoh MoreMsg
    endif
    echo r.gitcmd
    echo r.out->join("\n")
    echoh Normal
  endfor
  echo 'EOL'
enddef
