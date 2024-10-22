vim9script

g:ezpack_home = expand($'{&pp->split(',')[0]}/pack/ezpack')

var plugins = []

def MkParent(path: string): string
  const p = $'{path->substitute('[\/][^\/]*$', '', '')}'
  mkdir(p, 'p')
  return p
enddef

def GitPull(): list<any>
  redraw
  echo 'Ezpack: start jobs.'
  const l = plugins->len()
  var job_count = 0
  var cloned = []
  var results = []
  const current = getcwd()
  for p in plugins
    const s = p.opt ? ['opt', 'start'] : ['start', 'opt']
    const path = expand($'{g:ezpack_home}/{s[0]}/{p.name}')
    const extra = expand($'{g:ezpack_home}/{s[1]}/{p.name}')
    if isdirectory(extra) && !isdirectory(path)
      rename(extra, path)
    endif
    var cwd = path
    var gitcmd = $'git pull'
    if !isdirectory(path)
      cwd = MkParent(path)
      gitcmd = $'git clone --depth=1 {p.url}'
      cloned += [path]
    endif
    var r = {
      label: p.label,
      err: [],
    }
    results += [r]
    const ExitCb = (job, status) => {
      ++job_count
      redraw
      echo $'Ezpack: ({job_count}/{l}) {gitcmd->split(' ')[1]} {p.label}'
    }
    const ErrCb = (ch, msg) => {
      if msg !~# '^Cloning'
        r.err += [msg]
      endif
    }
    if has('win32')
      job_start(gitcmd, { cwd: cwd, exit_cb: ExitCb, err_cb: ErrCb })
    else
      # too many jobs kill vim on sakura rental server.
      ExitCb(0, 0)
      chdir(cwd)
      const msg = system(gitcmd)
      if v:shell_error !=# 0 && v:shell_error !=# 128
        ErrCb(0, msg)
      endif
    endif
  endfor
  chdir(current)
  if job_count < l
    redraw
    echo $'Ezpack: (0/{l}) wait for install.'
  endif
  while job_count < l
    sleep 50m
  endwhile
  for r in results->filter((i, v) => !!v.err)
    echoe r.label
    for e in r.err
      echoe e
    endfor
  endfor
  return cloned
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
  doautocmd User EzpackInstallPre
  const cloned = GitPull()
  const autoCmdPath = CreateAutocmd()
  ExecuteCloned(cloned)
  execute 'source' autoCmdPath
  redraw
  echo 'Ezpack: COMPLETED.'
enddef

