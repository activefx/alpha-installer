module AlphaInstaller
  MAJOR_VERSION = 0
  MINOR_VERSION  = 0
  PATCH_VERSION  = 2
  BUILD_VERSION  = 'alpha'

  VERSION = [MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION, BUILD_VERSION].compact.join('.')
end

