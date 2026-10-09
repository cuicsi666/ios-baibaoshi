# 百宝箱宿主 Podfile —— 官方 add-to-app Flutter module 集成
# 哔哩 module 位于 ./bili_module (CI 时 checkout)
platform :ios, '16.0'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Baibaoshi', {
  'Debug' => :debug,
  'Release' => :release,
}

flutter_application_path = 'bili_module'
load File.join(flutter_application_path, '.ios', 'Flutter', 'podhelper.rb')

target 'Baibaoshi' do
  use_frameworks!
  use_modular_headers!
  install_all_flutter_pods(flutter_application_path)
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
  flutter_post_install(installer) if defined?(flutter_post_install)
  # 宿主 target 显式注入 module 路径(target级优先级最高, 否则 xcode_backend 回退到 $SOURCE_ROOT/.. 不存在)
  installer.user_project.targets.each do |t|
    next unless t.name == 'Baibaoshi'
    t.build_configurations.each do |config|
      config.build_settings['FLUTTER_APPLICATION_PATH'] = '$(SRCROOT)/bili_module'
    end
  end
  installer.user_project.save
end