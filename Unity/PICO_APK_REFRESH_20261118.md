# PICO 4 APK 重打包 · 2026-11-18

本轮按用户“将最新三个游戏打包到桌面”开始，随后收到“等抓娃娃最后的改动，先完成过马路的打包”。已优先完成过马路，并保留已完成的推箱子交付；抓娃娃候选构建虽完成，但不发布为最终版，等待修改定稿后重打。

桌面目录：`C:\Users\Ait\Desktop\Neuralife-PICO4-最新APK-20261118-1606`。包含两份 APK、安装说明及 SHA-256 校验清单。

| 游戏 | 构建输出 | 大小（字节） | SHA-256 |
|---|---|---:|---|
| 过马路 | `PICO-Android-20261118T081118136` | 23881526 | `d8ede8ee415eb2be78a6bd3e4b3db29e3143bae1c881eb851b1e47255cd0b17e` |
| 推箱子 | `PICO-Android-20261118T080635000` | 22823594 | `1606cf3490cd587edc6f129216d4bd552565817497a8014a8f370ad2891a34f1` |

两份 Android 构建均使用本机 Unity 2022.3.62f3c1 配套 Android 工具链，最终 Unity/构建工具自然退出 0。APK ZIP 完整性、IL2CPP ARM64、OpenXR 原生库、各自应用 ID、PICO VR manifest 标记及 apksigner 验签通过；复制后的文件哈希一致。Assets/Packages 在各自最终构建前后未变化；构建时 ProjectSettings 指纹在各 build-manifest 中，工具按流程临时切换 Android 输入后端并还原。

过马路首轮因共享 Gradle daemon 收到 stop 命令失败；改用独立 GRADLE_USER_HOME `C:/Users/Ait/.gp1606` 及无常驻 daemon 设置后重建通过。保留失败和成功日志，未删除旧包。

证据：根仓库 `BuildOutput/PICO-APK-Refresh-20261118-160609/`；推箱子 `BuildOutput/PICO-Validation-20261118T080610045177/`；过马路 `BuildOutput/PICO-Validation-20261118T081107154888/` 及各自 APK 同目录的构建/验签清单。

本轮未安装到头显、未进行真机验收，headsetAcceptance 保持 NOT_TESTED；未重跑整套玩法回归、不修改 V5 通过项，也未覆盖正式宿主。抓娃娃不在本次桌面交付清单中。


## 抓娃娃补齐

用户确认加入后，使用最终三关版构建 `PICO-Android-20261118T081337248`，重新通过签名与包结构检查并核对复制后哈希 `c894a29c20bb6dabfb9ca24098a9d988d7a067a1c892b51296a3d323f4b2853a`。当前与 Android 构建工作目录的 295 个 Assets/Packages 文件中仅自动生成的 `Assets/Resources/PICOProjectSetting.asset.meta` 不同，游戏源码及资源内容一致。桌面目录现含三个 APK，完整清单已更新；抓娃娃头显名称 `ClawMachine`，仍未做头显实测。
