vim9script

g:ezpack_home = get(g:, 'ezpack_home', expand($'{&pp->split(',')[0]}/pack/ezpack'))

var plugins: list<any> = []
var results: list<any> = []

def MkParent(path: string): string
  const p = path->fnamemodify(':p:h')
  mkdir(p, 'p')
  return p
enddef

def GitPull()
  const l = plugins->len()
  redraw
  echo $'Ezpack: (0/{l}) wait for install.'
  var job_count = 0
  results = []
  const current = getcwd()
  for p in plugins
    var r = add(results, {
      label: p.label,
      path: p.path,
      cwd: p.path,
      gitcmd: 'git pull',
      status: -1,
      out: [],
      start: p.start,
      isnew: false,
      updated: false,
      cloned: false,
      errored: false,
    })[-1]
    if p.disable
      ++job_count
      r.cwd = MkParent(p.dis)
      r.gitcmd = $'mv {p.path} {p.dis}'
      r.out = ['']
      if isdirectory(p.path)
        redraw
        echo $'Ezpack: ({job_count}/{l}) disable {r.label}'
        r.status = rename(p.path, p.dis)
        r.updated = true
      else
        r.status = 0
      endif
      continue
    elseif isdirectory(p.extra) && !isdirectory(p.path)
      rename(p.extra, p.path)
    elseif isdirectory(p.dis) && !isdirectory(p.path)
      rename(p.dis, p.path)
      r.isnew = true
    endif
    if !isdirectory(p.path)
      r.isnew = true
      r.cwd = MkParent(p.path)
      r.gitcmd = $'git clone --depth=1 {p.url}'
    endif
    const ExitCb = (job, status) => {
      ++job_count
      r.status = isdirectory(r.path) ? status : -1
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
  for r in results
    r.out = r.out->flattennew()
    if r.status !=# 0 && r.status !=# 128
      r.errored = true
    elseif r.isnew
      r.cloned = true
    elseif !!r.out[0] && r.out[0]->trim() !=# 'Already up to date.'
      r.updated = true
    endif
  endfor
enddef

def ExecuteClonedStartPlugins()
  for r in results
    if r.isnew && r.start
      &rtp = $'{r.path},{&rtp}'
      for f in globpath($'{r.path}/plugins', '*.vim')
        execute 'source' f
      endfor
    endif
  endfor
enddef

def CreateAutocmd(): string
  var lazys = []
  var cmds = []
  var maps = []
  var lines = ['vim9script', 'augroup ezpack', '  au!']
  for p in plugins
    if p.lazy
      lazys += [p.name]
    endif
    for o in p.on
      lines += [$'  au {o} ++once packadd {p.name}']
    endfor
    for c in p.cmd
      cmds += [$'command! -nargs=* {c} delc {c}|packadd {p.name}|{c} <args>']
    endfor
    for m in p.map
      maps += [$'{m.map} {m.key} <Cmd>u{m.map} {m.key->substitute('<', '<lt>', 'g')}<Bar>packadd {p.name}<CR>{m.key}']
    endfor
  endfor
  if !!lazys
    lines += ['  au SafeStateAgain * ++once LazyLoad(0)']
  endif
  lines += ['augroup END']
  if !!lazys
    lines += ['const plugins = [']
    for name in lazys
      lines += [$"  '{name}',"]
    endfor
    lines += [
      ']',
      'var index = 0',
      'const max = len(plugins)',
      "const interval = get(g:, 'ezpack_lazy_interval', 5)",
      'def LazyLoad(t: number)',
      '  if index < max',
      "    execute 'packadd' plugins[index]",
      '    ++index',
      '    timer_start(interval, LazyLoad)',
      '  endif',
      'enddef'
    ]
  endif
  lines += cmds
  lines += maps
  const path = expand($'{g:ezpack_home}/start/_/plugin/_.vim')
  MkParent(path)
  writefile(lines, path)
  return path
enddef

def SimpleLog()
  var logs = []
  for r in results
    if r.errored
      add(logs, $'- Error {r.label}')
    elseif r.updated
      add(logs, $'- Updated {r.label}')
    elseif r.cloned
      add(logs, $'- Cloned {r.label}')
    endif
  endfor
  if !!logs
    echow $'Ezpack:'
    for l in logs
      echow l
    endfor
  endif
enddef

# -----------------------
# Interface

export def Init()
  plugins = []
enddef

export def Ezpack(...fargs_src: list<any>)
  var fargs = []
  for a in fargs_src
    if typename(a) ==# 'string' && a[0] ==# '#'
      break
    endif
    fargs += [a]
  endfor
  const name = fargs[0]->matchstr('[^/]*$')->substitute('\.git$', '', '')
  var p = add(plugins, {
    label: fargs[0],
    url: fargs[0] =~# '\.git$' ? fargs[0] : $'https://github.com/{fargs[0]}.git',
    name: name,
    # Paths
    start: true,
    path: expand($'{g:ezpack_home}/start/{name}'),
    extra: expand($'{g:ezpack_home}/opt/{name}'),
    dis: expand($'{g:ezpack_home}/disable/{name}'),
    # Options
    lazy: false,
    disable: false,
    on: [],
    cmd: [],
    map: [],
  })[-1]
  if 1 < len(fargs)
    p.start = false
    [p.path, p.extra] = [p.extra, p.path]
  endif
  var i = 0
  while true
    ++i
    const a = get(fargs, i, '')
    if !a
      break
    endif
    if a ==# '<opt>'
      # nop
    elseif a ==# '<lazy>'
      p.lazy = true
    elseif a ==# '<disable>'
      p.disable = true
    elseif a ==# '<on>'
      add(p.on, fargs[i + 1 : i + 2]->join(' '))
      i += 2
    elseif a ==# '<cmd>'
      ++i
      add(p.cmd, fargs[i])
    elseif a =~# '<[nixovct]\?map>'
      ++i
      add(p.map, { map: a->substitute('[<>]', '', 'g'), key: fargs[i] })
    else
      echoh ErrorMsg
      echom $'Ezpack: Bad argument: "{a}"'
      echoh Normal
    endif
  endwhile
enddef

export def Install()
  if exists('#User#EzpackInstallPre')
    doautocmd User EzpackInstallPre
  endif
  GitPull()
  ExecuteClonedStartPlugins()
  const autoCmdPath = CreateAutocmd()
  execute 'source' autoCmdPath
  redraw
  if !has('vim_starting')
    SimpleLog()
  endif
  if results->indexof((i, v) => v.errored) !=# -1
    echoh ErrorMsg
    echom 'Ezpack: FAILED! See :EzpackLog.'
  elseif results->indexof((i, v) => v.updated) !=# -1
    echoh WarningMsg
    echom 'Ezpack: Some pulgins are updated, plz restart vim.'
  else
    echo 'Ezpack: COMPLETED.'
  endif
  echoh Normal
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
  var paths = [expand($'{g:ezpack_home}/start/_')]
  for p in plugins
    add(paths, expand(p.path))
  endfor
  const dirs =
    globpath($'{g:ezpack_home}/start', '*')->split("\n") +
    globpath($'{g:ezpack_home}/opt', '*')->split("\n")
  for d in dirs
    if index(paths, d) !=# -1
      continue
    endif
    if !isdirectory($'{d}/plugin') && !isdirectory($'{d}/autoload')
      continue
    endif
    if input($'rm {d} (y/n): ') != 'y'
      continue
    endif
    delete(d, 'rf')
  endfor
  redraw
  echo 'Ezpack: COMPLETED.'
enddef

export def Log()
  for r in results
    echo r.label
    if r.errored
      echoh ErrorMsg
    elseif r.cloned || r.updated
      echoh WarningMsg
    else
      echoh MoreMsg
    endif
    echo $'path: {r.path}'
    echo $'cd {r.cwd}'
    echo r.gitcmd
    echo r.out->join("\n")
    echoh Normal
  endfor
  echo 'EOL'
enddef
