Pod::Spec.new do |s|
  s.name         = 'HJCache'
  s.version      = '2.0.0'
  
  s.ios.deployment_target = '9.0'
  
  s.summary      = 'High performance cache framework for iOS'
  s.homepage     = 'https://github.com/ObjectiveC-Lib/HJCache'
  s.source       = { :git => 'https://github.com/ObjectiveC-Lib/HJCache.git', :tag => s.version }
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = { 'navy' => 'lzxy169@gmail.com' }
  
  s.requires_arc = true
  s.frameworks   = 'UIKit', 'CoreFoundation', 'QuartzCore'
  
  s.source_files = 'HJCache/Core/HJCache.h'
  s.default_subspec = 'Core'
  
  s.subspec 'Core' do |core|
    core.source_files = 'HJCache/Core/*.{h,m}'
  end
  
  s.subspec 'Default' do |default|
    default.source_files = 'HJCache/Default/*.{h,m}'
    default.framework = 'Photos', 'AVFoundation'
    default.dependency 'HJCache/Core'
    default.dependency 'YYImage'
  end
  
  s.subspec 'SDBridge' do |sdbridge|
    sdbridge.source_files = 'HJCache/SDBridge/*.{h,m}'
    sdbridge.dependency 'HJCache/Core'
    sdbridge.dependency 'SDWebImage'
  end
end
