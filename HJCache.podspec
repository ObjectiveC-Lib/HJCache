Pod::Spec.new do |s|
  s.name         = 'HJCache'
  s.version      = '1.0.0'
  
  s.platform     = :ios, '6.0'
  s.ios.deployment_target = '6.0'
  
  s.summary      = 'High performance cache framework for iOS'
  s.homepage     = 'https://github.com/ObjectiveC-Lib/HJCache'
  s.source       = { :git => 'https://github.com/ObjectiveC-Lib/HJCache.git', :tag => s.version }
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = { 'navy' => 'lzxy169@gmail.com' }
  
  s.requires_arc = true
  s.libraries    = 'sqlite3'
  s.frameworks   = 'UIKit', 'CoreFoundation', 'QuartzCore'
  
  s.source_files = 'HJCache/HJCache.h'
#  s.default_subspec = 'Core'

  s.subspec 'Core' do |core|
    core.source_files = 'HJCache/Core/*.{h,m}'
  end
  
  s.subspec 'Default' do |df|
    # df.ios.deployment_target = '9.0'
    df.source_files = 'HJCache/Default/*.{h,m}'
    df.framework = 'Photos', 'AVFoundation'
    df.dependency 'HJCache/Core'
    # df.dependency 'YYImage'
  end
  
end
