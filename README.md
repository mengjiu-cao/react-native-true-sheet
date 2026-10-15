# React Native TrueSheet

[![CI](https://github.com/lodev09/react-native-true-sheet/actions/workflows/checks.yml/badge.svg)](https://github.com/lodev09/react-native-true-sheet/actions/workflows/checks.yml)
[![NPM Downloads](https://img.shields.io/npm/d18m/%40lodev09%2Freact-native-true-sheet)](https://www.npmjs.com/package/@lodev09/react-native-true-sheet)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/lodev09/react-native-true-sheet)

The true native bottom sheet experience for your React Native Apps. 💩

<img alt="React Native True Sheet - iPad" src="docs/static/img/preview-ipad.gif" width="744" /><br>
<img alt="React Native True Sheet - IOS" src="docs/static/img/preview-ios.gif" width="248" height="500" /><img alt="React Native True Sheet - Android" src="docs/static/img/preview-android.gif" width="248" height="500" /><img alt="React Native True Sheet - Web" src="docs/static/img/preview-web.gif" width="248" height="500" />

## Features

* ⚡ **Powered by Fabric** - Built on React Native's new architecture for maximum performance
* 🚀 **Fully Native** - Implemented in the native realm, zero JS hacks
* ♿ **Accessible** - Native accessibility and screen reader support out of the box
* 🔄 **Flexible API** - Use [imperative methods](https://sheet.lodev09.com/reference/methods#ref-methods) or [lifecycle events](https://sheet.lodev09.com/reference/events)
* ⌨️ **Keyboard Handling** - Built-in [keyboard handling](https://sheet.lodev09.com/guides/keyboard) with automatic adjustment
* 📐 **Side Sheets** - Native [side sheet](https://sheet.lodev09.com/guides/side-sheets) support for iPad and Android tablets
* 🪟 **Liquid Glass** - [iOS 26+ Liquid Glass](https://sheet.lodev09.com/guides/liquid-glass) support out of the box, featured in [Expo Blog](https://expo.dev/blog/how-to-create-apple-maps-style-liquid-glass-sheets)
* 🐎 **Reanimated** - First-class support for [react-native-reanimated](https://sheet.lodev09.com/guides/reanimated)
* 🧭 **React Navigation** - Built-in [sheet navigator](https://sheet.lodev09.com/guides/navigation) for seamless navigation integration
* 🌐 **Web Support** - Full [web support](https://sheet.lodev09.com/guides/web) out of the box

## Installation

> [!IMPORTANT]
> **Version 3.0+ requires React Native's New Architecture (Fabric)**
> For the old architecture, use version 2.x. See the [Migration Guide](https://sheet.lodev09.com/migration) for upgrading.

### Prerequisites

- React Native 0.81+
- New Architecture enabled
- Xcode 26.1+

### Compatibility

| TrueSheet | React Native | Expo SDK |
|-----------|--------------|----------|
| 3.7+      | 0.81+        | 54+      |
| 3.6       | 0.80         | 52-53    |

### Expo

```sh
npx expo install @lodev09/react-native-true-sheet
```

### Bare React Native

```sh
yarn add @lodev09/react-native-true-sheet
cd ios && pod install
```

## Documentation

- [Example](example)
- [Configuration](https://sheet.lodev09.com/reference/configuration)
- [Lifecycle Events](https://sheet.lodev09.com/reference/events)
- [React Navigation](https://sheet.lodev09.com/guides/navigation)
- [Troubleshooting](https://sheet.lodev09.com/troubleshooting)
- [Testing with Jest](https://sheet.lodev09.com/guides/jest)
- [Migrating to v3](https://sheet.lodev09.com/migration)

## Usage

```tsx
import { TrueSheet } from "@lodev09/react-native-true-sheet"

export const App = () => {
  const sheet = useRef<TrueSheet>(null)

  // Present the sheet ✅
  const present = async () => {
    await sheet.current?.present()
    console.log('horray! sheet has been presented 💩')
  }

  // Dismiss the sheet ✅
  const dismiss = async () => {
    await sheet.current?.dismiss()
    console.log('Bye bye 👋')
  }

  return (
    <View>
      <Button onPress={present} title="Present" />
      <TrueSheet
        ref={sheet}
        detents={['auto', 1]}
      >
        <Button onPress={dismiss} title="Dismiss" />
      </TrueSheet>
    </View>
  )
}
```

## SmartX 维护分支

`smartx-ios-sheet` 基于上游 3.11.14，版本 `3.11.14-smartx.1`。维护仓库为
[`mengjiu-cao/react-native-true-sheet`](https://github.com/mengjiu-cao/react-native-true-sheet)，
保留 3.x 的 scrollable、footer、detents 与事件 API，不迁移到 4.0 beta。

以下扩展仅用于 iOS；Android 显式忽略，不改变其外观：

| Prop | 默认与行为 |
| --- | --- |
| `edgeToEdge` | 默认 `false`；iOS 26+ 手机 page sheet 去除系统装饰缩放及外围留白。iPad、form 和显式窄宽度保持系统布局；全窗口 `maxContentWidth` 仍可启用。 |
| `backgroundColor` | 既有属性；原生 surface 背景承载覆盖内容、grabber 与安全区，不依赖应用补丁。 |
| `dimColor` / `dimOpacity` | 两者均省略时沿用系统蒙层；只传颜色时 opacity 为 0.5，只传 opacity 时颜色为黑。opacity 限制在 0–1，0 仍拦截模态背景触摸，`dimmed=false` 才允许穿透。 |
| `topBorderWidth` / `topBorderColor` | 默认宽度 0；颜色省略时用系统 separator。只描顶部及上两角，不描底边、不增加布局高度。 |
| `topLeftCornerRadius` / `topRightCornerRadius` | 独立覆盖上角，0 为直角；省略的一侧沿用 `cornerRadius` 或系统圆角。 |

```tsx
<TrueSheet
  edgeToEdge
  backgroundColor="#111111"
  dimColor="#000000"
  dimOpacity={0.5}
  cornerRadius={20}
  topBorderWidth={1}
  topBorderColor="#333333"
  topLeftCornerRadius={20}
  topRightCornerRadius={20}
>
  {children}
</TrueSheet>
```

SmartX 接入时不设置新的 border/radius 值，保持现有主题、抓手、内容与默认无描边；
示例中的描边仅展示可选能力。旧 Android 窗口高度、iOS 已可见输入框不反复滚动的修正已并入源码。
蒙层由库自行持有，关闭转场取消后恢复，堆叠与卸载释放保持原生命周期；不再修改 UIKit 的 DimmingView。

去留白参考 native-sheet 的 view 容器实现，仍需有界识别本 sheet 的 UIKit
`UIDropShadowView` 祖先。该系统内部结构不是公共 API；布局/系统版本改变需要重新做设备视觉验证。
无设备几何烟测与原生编译不等于 iOS 26/27 的短内容、拖拽取消、堆叠和键盘视觉验收。

构建与离线接入：`yarn install --immutable` → `yarn prepare` →
`yarn pack --out <输出目录>/react-native-true-sheet-3.11.14-smartx.1.tgz`。
应用通过仓库内 `file:` tarball 锁定本版本，无个人绝对路径依赖；更新原生代码后须重建开发包，JS reload 不生效。

## AI Skills

Skills are reusable AI capabilities that give your AI coding agent knowledge about TrueSheet. With the right skill loaded, your agent can pick the right patterns, avoid common mistakes, and generate correct code without you having to explain the library every time.

```sh
npx skills add lodev09/react-native-true-sheet
```

This will install the **TrueSheet Usage** skill into your project.

## That map is awesome!

Yes it is! Checkout [`@lugg/maps`](https://github.com/lugg/maps), a universal maps library for React Native that I'm developing at [Lugg](https://lugg.com).

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

[MIT](LICENSE)

---

Made with ❤️ by [@lodev09](http://linkedin.com/in/lodev09/)
