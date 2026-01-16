vim9script

command! -nargs=* Ezpack ezpack#Ezpack(<f-args>)
command! EzpackInit ezpack#Init()
command! EzpackLog ezpack#Log()
command! EzpackInstallToStart ezpack#SetupDefaultOptions({ start: true, lazy: false })
command! EzpackInstallToOpt ezpack#SetupDefaultOptions({ start: false, lazy: false })
command! EzpackLazyLoad ezpack#SetupDefaultOptions({ start: false, lazy: true })
command! -nargs=* EzpackPost ezpack#EzpackPost(<f-args>)
