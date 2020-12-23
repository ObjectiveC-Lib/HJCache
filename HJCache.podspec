Pod::Spec.new do |s|
  s.name         = 'HJCache'
  s.summary      = 'High performance cache framework for iOS.'
  s.version      = '1.0.0'
  s.license      = "MIT"
  s.author       = { "navy" => "lzxy169@gmail.com" }
  s.homepage     = "./"
  s.platform     = :ios, '6.0'
  s.ios.deployment_target = '6.0'
  s.source       = { :path => './' , :tag => s.version.to_s }
  
  s.requires_arc = true
  s.source_files = 'HJCache/*.{h,m}'
  s.public_header_files = 'HJCache/*.{h}'
  
  s.libraries = 'sqlite3'
  s.frameworks = 'UIKit', 'CoreFoundation', 'QuartzCore' 
end
