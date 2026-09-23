Pod::Spec.new do |s|
  s.name             = 'SwiftUp'
  s.version          = '0.1.2'
  s.summary          = 'Swift shallow wrapper of Apple SDK.'

  s.description      = <<-DESC
Swift shallow wrapper of Apple SDK.
Apple starts to provide Swift API for their libraries, but it is slow and
imperfect. These projects fill the gap.
                       DESC

  s.homepage         = 'https://github.com/youknowone/SwiftUp'
  s.license          = { :type => '2-clause BSD', :file => 'LICENSE' }
  s.author           = { 'Jeong YunWon' => 'jeong@youknowone.org' }
  s.source           = { :git => 'https://github.com/youknowone/SwiftUp.git', :tag => s.version.to_s }

  s.platform = :osx
  s.osx.deployment_target = "10.10"

  s.dependency "SwiftIOKit", "~> 0.1.2"
  s.dependency "SwiftCarbon", "~> 0.1.0"
  s.dependency "SwiftCoreServices", "~> 0.1.1"

  s.swift_versions = '5.0'
end
