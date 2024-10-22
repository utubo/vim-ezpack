vim9script

g:ezpack_home = expand($'{&pp->split(',')[0]}/pack/ezpack')

var plugins = []

def MkParent(path: string)
  mkdir($'{path->substitute('[\/][^\/]*$', '', '')}', 'p')
enddef

def GitPull(): list<any>
  var cloned = []
  const l = plugins->len()
  var i = 0
  for p in plugins
    i += 1
    const s = p.opt ? ['opt', 'start'] : ['start', 'opt']
    const path = expand($'{g:ezpack_home}/{s[0]}/{p.name}')
    const extra = expand($'{g:ezpack_home}/{s[1]}/{p.name}')
    if isdirectory(extra) && !isdirectory(path)
      rename(extra, path)
    endif
    var gitcmd = $'git pull {path}'
    if !isdirectory(path)
      MkParent(path)
      gitcmd = $'git clone {p.url} {path}'
      cloned += [path]
    endif
    echo $'Ezpack: ({i}/{l}) {gitcmd->split(' ')[1]} {p.label}'
    const result = system(gitcmd)
    if v:shell_error !=# 0 && v:shell_error !=# 128
      echoe gitcmd
      echoe result
    endif
    redraw
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
  echo 'Ezpack: COMPLETED.'
enddef

