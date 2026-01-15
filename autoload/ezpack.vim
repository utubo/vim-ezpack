vim9script

g:ezpack_home = get(g:, 'ezpack_home', expand($'{&pp->split(',')[0]}/pack/ezpack'))

var plugins: list<any> = []
var results: list<any> = []
var default_options: any = {}

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
  g:ezpack_num_threads = get(g:, 'ezpack_num_threads', 9)
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
      var b = !p.branch ? '' : $'-b {p.branch} '
      r.gitcmd = $'git clone {b}--depth=1 {p.url}'
    endif
    const ExitCb = (job, status) => {
      ++job_count
      r.status = isdirectory(r.path) ? status : -1
      redraw
      echo $'Ezpack: ({job_count}/{l}) {r.gitcmd->split(' ')[1]} {r.label}'
    }
    const OutCb = (ch, msg) => add(r.out, [msg])
    if g:ezpack_num_threads < 2
      chdir(r.cwd)
      OutCb(0, [system(r.gitcmd)])
      ExitCb(0, v:shell_error)
    else
      while g:ezpack_num_threads < job_count
        sleep 50m
      endwhile
      job_start(r.gitcmd, { cwd: r.cwd, exit_cb: ExitCb, out_cb: OutCb, err_cb: OutCb })
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
    const pk = (p.pre + [$'packadd {p.name}'] + p.post)->join('|')
    if p.lazy
      lazys += [pk]
    endif
    for o in p.on
      lines += [$'  au {o} ++once {pk}']
    endfor
    for c in p.cmd
      cmds += [$'silent! command -nargs=* {c} delc {c}|{pk}|{c} <args>']
    endfor
    for m in p.map
      maps += [$'{m.map} {m.key} <Cmd>u{m.map} {m.key->substitute('<', '<lt>', 'g')}<Bar>{pk->substitute('|', '<BAR>', 'g')}<CR>{m.key}']
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
      '    execute plugins[index]',
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

def AddParam(p: dict<any>, param: dict<any>)
  if !!param.name
    p[param.name] += [param.value->join(' ')]
  endif
  param.name = ''
  param.value = []
enddef

# -----------------------
# Interface

export def Init()
  plugins = []
  SetupDefaultOptions({ start: true, lazy: false })
enddef

export def SetupDefaultOptions(options: any)
  default_options = options
enddef

export def Ezpack(...fargs: list<any>)
  var p = {
    label: '',
    url: '',
    branch: '',
    name: '',
    # Path
    start: true,
    path: '',
    extra: '',
    dis: '',
    # Options
    lazy: false,
    disable: false,
    on: [],
    cmd: [],
    map: [],
    pre: [],
    post: [],
  }->extend(default_options)
  var param = { name: '', value: [] }
  var i = -1
  const max = len(fargs) - 1
  while i < max
    ++i
    var more = false
    const a = fargs[i]
    if typename(a) ==# 'string' && a[0] ==# '#'
      break
    elseif a ==# '<start>'
      p.start = true
    elseif a ==# '<opt>'
      p.start = false
    elseif a ==# '<lazy>'
      p.start = false
      p.lazy = true
    elseif a ==# '<disable>'
      p.start = false
      p.disable = true
    elseif a ==# '<on>'
      p.start = false
      add(p.on, fargs[i + 1 : i + 2]->join(' '))
      i += 2
    elseif a ==# '<cmd>'
      p.start = false
      ++i
      p.cmd += fargs[i]->split(',')
    elseif a =~# '<[nixovct]\?map>'
      p.start = false
      ++i
      add(p.map, { map: a->substitute('[<>]', '', 'g'), key: fargs[i] })
    elseif a ==# '<branch>'
      ++i
      p.branch = fargs[i]
    elseif a ==# '<pre>'
      p->AddParam(param)
      param.name = 'pre'
      more = true
    elseif a ==# '<post>'
      p->AddParam(param)
      param.name = 'post'
      more = true
    elseif !!param.name
      param.value += [a]
      more = true
    elseif !p.name
      p.label = a
      p.url = a =~# '\.git$' ? a : $'https://github.com/{a}.git'
      const name = a->matchstr('[^/]*$')->substitute('\.git$', '', '')
      p.name = name
      p.path = expand($'{g:ezpack_home}/start/{name}')
      p.extra = expand($'{g:ezpack_home}/opt/{name}')
      p.dis = expand($'{g:ezpack_home}/disable/{name}')
    else
      throw $'Ezpack: Bad argument: "{a}"'
    endif
    if !more
      p->AddParam(param)
    endif
  endwhile
  p->AddParam(param)
  if !p.name
    throw $'Ezpack: Plugin-name is not found: {fargs->join(' ')}'
  endif
  if !p.start
    [p.path, p.extra] = [p.extra, p.path]
  endif
  add(plugins, p)
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
