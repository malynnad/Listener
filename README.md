# Listener

本地音乐、B 站音源与网络电台合一的播放器，Flutter 实现，macOS 与 Android 双端。

## 功能

**本地音乐**
- 桌面端选文件夹递归扫描；Android 申请媒体权限后扫描 Music / Download / Documents 等约定目录，也可手动多选文件
- 读取标签与内嵌封面，支持 MP3 / FLAC / M4A / AAC / WAV / OGG / OPUS / WMA / APE
- 曲库索引本地缓存，重启不重复解析；支持按曲名、艺人、专辑实时过滤

**B 站**
- 关键词搜索视频，直接抽取其中的音轨播放
- 扫码登录（passport 二维码流程），登录态存入系统钥匙串
- 按账号权限自动选择最高码率音轨（64K / 132K / 192K / Dolby / Hi-Res FLAC）
- 下载音轨到本地，桌面端有 ffmpeg 时无损转封装为 `.m4a`

**电台**
- 数据源为 [radio-browser.info](https://www.radio-browser.info/)，镜像自动发现与故障转移
- 热门电台、关键词搜索、按国家筛选、收藏

**通用**
- 统一播放队列（三个来源混排）、循环 / 单曲循环 / 随机
- 队列持久化，重启恢复到上次的曲目列表
- 宽屏侧边栏、窄屏底部导航的响应式布局

## 技术选型要点

| 决策 | 原因 |
|---|---|
| `media_kit`（mpv）而非 `just_audio` | B 站音轨必须带 `Referer: https://www.bilibili.com` 才不返回 403，而 `<audio>` / 系统播放器无法为媒体请求单独注入请求头。`media_kit` 的 `Media(httpHeaders:)` 直接解决，无需自建本地代理 |
| 自研 WBI 签名 | 未复用任何 GPL 项目代码，仅依据公开接口文档实现；`test/wbi_test.dart` 用公开测试向量校验 mixinKey |
| JSON 文件存储而非 SQLite | 曲库索引与收藏在数万条量级下 JSON 足够，少一个原生依赖就少一类平台构建问题 |
| 扫描放进 isolate | 5000 首的标签读取约 3~6 秒，在主 isolate 会直接卡住界面 |

## 构建

环境要求：

- Flutter 3.50.0 / Dart 3.14.0
- Android：Android SDK 37（`permission_handler_android` 要求依赖方以 37 编译，故 `compileSdk` 显式写死 37）+ JDK（`flutter doctor` 通过即可）
- macOS：**需要完整安装 Xcode**。仅装 Command Line Tools 时 `xcodebuild` 不可用，无法编译桌面端

```bash
flutter pub get
flutter test          # WBI 签名与标题清洗的单测
flutter analyze       # 当前 0 error / 0 warning
flutter run -d macos  # 桌面端（需 Xcode）
flutter run -d <设备>  # Android
flutter build apk --release
```

### 构建排错

- **`gradlew assembleDebug` 报 `Operation not permitted`（写入 pub-cache 或 Flutter SDK 缓存）**：Gradle 守护进程若是在受限环境里启动的，会把该限制带给后续所有子进程。执行 `cd android && ./gradlew --stop && ./gradlew assembleDebug --no-daemon` 即可绕过，之后守护进程重建即恢复正常。
- **libmpv 下载失败**：`media_kit_libs_android_audio` 会从 GitHub Releases 拉 4 个 ABI 的预编译包，国内直连会超时。可先用镜像（如 `https://ghfast.top/https://github.com/...`）下载 `default-{arm64-v8a,armeabi-v7a,x86_64,x86}.jar` 到 `build/media_kit_libs_android_audio/v1.1.8/`，脚本校验 MD5 通过后会跳过下载。
- **Gradle wrapper 卡在 `-all.zip`**：`android/gradle/wrapper/gradle-wrapper.properties` 已改为本机缓存里已有的 `-bin` 发行包，避免拉取 200 MB 的全量包。

### 接口自检

B 站接口风控规则会变，签名链路出问题时先跑自检脚本，避免在 UI 里盲猜：

```bash
dart run tool/probe_bili.dart 周杰伦
```

脚本会依次打印 mixinKey、搜索结果、cid 与 playurl 返回的各档音轨码率。若这里通而应用不通，问题在播放器层；若这里就不通，问题在签名或 Cookie。

### 发布签名

`android/key.properties` 已被 `.gitignore` 排除（`android/.gitignore` 里声明的 `key.properties`、`**/*.jks`）。文件存在时 release 用其中的密钥签名，缺失则自动回退 debug 签名，保证别人 clone 下来就能构建。

```properties
storeFile=/绝对路径/listener.jks
storePassword=...
keyAlias=listener
keyPassword=...
```

当前密钥：`~/keystores/listener.jks`（RSA 4096，10000 天），证书 `CN=Listener`，
SHA-256 `FB:7C:78:A9:...:E3:F2`。**这把 key 丢了就无法升级已发布的包，务必离线备份。**

## 目录结构

```
lib/
├── main.dart                  # 入口，MediaKit 初始化
├── app.dart                   # Provider 装配 + 主题
├── controllers/
│   └── player_controller.dart # 队列、播放状态、循环/随机
├── core/                      # 配置、主题、JSON 存储、凭据、格式化
├── models/                    # Track（统一曲目）、RadioStation
├── services/
│   └── playback_service.dart  # mpv 封装
├── features/
│   ├── library/               # 本地扫描（isolate）、音乐库页
│   ├── bilibili/              # wbi 签名、接口、扫码登录、下载、页面
│   ├── radio/                 # radio-browser 客户端、页面
│   └── shell/                 # 应用外壳与导航
└── widgets/                   # 播放栏、封面、页头等共用组件

tool/
└── probe_bili.dart            # B 站接口自检脚本（纯 Dart，flutter 之外可直接跑）
```

## 合规说明

- **电台数据**：来自 radio-browser.info 的公开 REST 接口，该数据集由社区维护并公开导出，不属于任何第三方播放器的私有资产。按对方要求：请求携带可识别 User-Agent（`Listener/0.1`）、查询做 1 秒节流、界面标注数据来源。若要正式发布，请把 `lib/core/config.dart` 中的 UA 改成真实仓库地址。
- **B 站**：使用非官方 Web 接口，属于违反平台用户协议的行为。本项目仅用于个人学习与本地收听，不内置、不分发任何受版权保护的内容；下载产物仅保存在本机。
- **凭据**：`SESSDATA` 等 Cookie 通过 `flutter_secure_storage` 存入系统钥匙串，不写入日志、不提交仓库。
- **许可**：本项目为 MIT。未复制 hiqradio（无 LICENSE）、NeriPlayer 或 Mineradio（GPL-3.0）的任何代码。

## 已知限制

- 未接入 `audio_service`：Android 上没有通知栏控制与锁屏控制，退到后台仍可播放但操作需回到应用内
- 电台是直播流，没有时长概念：播放栏显示「直播中」而非进度条，不支持拖动
- 电台队列不循环：某台断流后停在原地并提示，不会自动跳到下一个台（避免看起来像"关不掉"）
- Android 只能扫描 `androidMusicRoots` 里列出的约定目录（系统媒体目录与主流播放器下载目录），不做全盘遍历；分区存储下无法枚举整块外部存储
- Android 上 `file_picker` 选中的文件是 SAF 内容 URI 的缓存副本，适合临时试听，不宜作为长期曲库；长期曲库请用「扫描手机音乐」
- Android 下载落在应用专属目录（`Android/data/com.listener.player/files/downloads`），写入公共 `Download` 目录需要 MediaStore 适配
- Android 端不内置 ffmpeg，DASH 音轨以分片 MP4 直接存为 `.m4a`，个别系统播放器可能不识别（mpv / VLC / ExoPlayer 正常）
- macOS 端关闭了 App Sandbox，换取任意目录的曲库扫描能力；上架 App Store 需改为 security-scoped bookmark
- 暂无歌词、无音频可视化（粒子效果未纳入本期范围）

## 真机验证记录

2026-11-27，OPPO PKR110（Android 16 / arm64），`app-release.apk`：

| 场景 | 结果 |
|---|---|
| 启动与三页导航（本地 / B站 / 电台） | 正常 |
| 媒体权限申请（READ_MEDIA_AUDIO） | 授权后扫描 5 个目录，读到 1 首，标签、码率、时长正确 |
| 本地曲目播放与进度推进 | 正常 |
| 重启后曲库与队列恢复 | 保留曲库，播放栏恢复上次曲目且保持暂停（不自动出声） |
| B 站搜索 | 返回真实结果 |
| B 站音轨拉流播放 | 正常，封面与进度均正确（说明 Referer 注入在 Android 生效） |
| 电台列表与流播放 | 拉到 100 个台，选中后正常起播 |

真机阶段修复的两个缺陷：

1. `Isolate.run` 的闭包直接引用了 `_folders`，捕获 `this` 把整个 Provider 对象图带进 isolate，扫描必然报 `object is unsendable`。改为先取本地副本再进闭包。
2. 未登录时 `nav` 接口返回 `code=-101`，`_mixin()` 把它当异常抛出，导致"没登录就搜不了 B 站"。`nav` 改为读 `data` 而不校验业务码。
