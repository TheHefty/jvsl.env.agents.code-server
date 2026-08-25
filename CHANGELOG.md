# Changelog

## [1.5.0](https://github.com/TheHefty/jvsl.env.agents.code-server/compare/v1.4.0...v1.5.0) (2026-08-25)


### Features

* ai-memory, per project and off unless asked for ([d414b42](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/d414b428dd07569ff6fc13a9cec8203e2696bc0e))
* ai-memory, per project and off unless asked for ([edd4263](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/edd426396158f17cdba9518e5531815b59af660f))

## [1.4.0](https://github.com/TheHefty/jvsl.env.agents.code-server/compare/v1.3.0...v1.4.0) (2026-08-25)


### Features

* forward GH_TOKEN into the jail, when there is one ([7e740c5](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/7e740c5125ccf0a91d296ca11603419a04af1bbe))
* forward GH_TOKEN into the jail, when there is one ([1d2bd4f](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/1d2bd4f36517df52b1d21fc42dd1c2be0fd93fee))

## [1.3.0](https://github.com/TheHefty/jvsl.env.agents.code-server/compare/v1.2.0...v1.3.0) (2026-08-25)


### Features

* jail the Claude Code CLI by default ([9092c6b](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/9092c6b5bfcf6ab1ccad843a4a78374e98f79c3e))
* jail the Claude Code CLI by default ([f171c6b](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/f171c6bd357df264d98b354ccbe375ee13016846))


### Bug Fixes

* pin ai-jail, whose defaults move under the image ([17aafc6](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/17aafc60411bc89e697736b43ad305a9ef41c8cf))

## [1.2.0](https://github.com/TheHefty/jvsl.env.agents.code-server/compare/v1.1.1...v1.2.0) (2026-08-15)


### Features

* a pre-push hook, running the half of CI that is cheap ([e840628](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/e840628d27b4fe2f2898a400ca64f5a0f1fd28ff))
* **core:** the menu bar, two extensions, and defaults that reach an environment already running ([0ed85a3](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/0ed85a3689f09df5e6ac9e434e85ca235e4c4b65))
* init prepares the host, dev opens the environment ([2770865](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/27708652b61ec9009283a7aea31650eb9b581965))
* the container's limits are the project's, in the manifest ([57d0ebd](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/57d0ebd36a8397b57161e86ad2a6e7750030b453))
* the window's buttons go in the bar code-server already draws ([e459527](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/e459527a80d6aad151031d8483a18e3b9a890d85))


### Bug Fixes

* **python:** add the PPA without asking the Launchpad API ([a74990e](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/a74990ef0f58bc89e589cc7a8330f52f0a8a9db8))

## [1.1.1](https://github.com/TheHefty/jvsl.env.agents.code-server/compare/v1.1.0...v1.1.1) (2026-08-10)


### Bug Fixes

* **docker:** give rootlesskit a port driver, so -p means something ([ec6684b](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/ec6684b9fe20ff5bfc411d576968246de5ad5286))

## [1.1.0](https://github.com/TheHefty/jvsl.env.agents.code-server/compare/v1.0.2...v1.1.0) (2026-08-03)


### Features

* **core:** install git-lfs and register its filters system-wide ([#10](https://github.com/TheHefty/jvsl.env.agents.code-server/issues/10)) ([55ea5ee](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/55ea5ee02cd68ce17a3b0ff9a250d8465749fe5a))

## [1.0.2](https://github.com/TheHefty/jvsl.env.agents.code-server/compare/v1.0.1...v1.0.2) (2026-08-03)


### Bug Fixes

* keep start/Cargo.lock in sync with the released version ([9f2d73f](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/9f2d73fc904ec1c690950349084d6ed7eba6f537))

## [1.0.1](https://github.com/TheHefty/jvsl.env.agents.code-server/compare/v1.0.0...v1.0.1) (2026-08-03)


### Documentation

* correct the README's core layer and stack list ([4b18ead](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/4b18ead28239c1f26915a6535dbd45ef22d4fcce))

## 1.0.0 (2026-08-03)


### Features

* add android stack, requiring java as a dependency ([1332c4c](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/1332c4c758337bbe87b567a9aea7e7e967cf31f1))
* add C/C++ stack ([61a01dc](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/61a01dc98ac6b6edfd30ea298358741b3fc2961d))
* add dotnet, python, golang, ruby, and php stacks ([911da53](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/911da53332c5cc1ddf26b701eb39fce6f7653e40))
* add node stack, per-stack extensions, and relocate manifest to repo root ([e228a6f](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/e228a6fac1152e694245b188adf0833b058d4c4a))
* add rust stack ([8cc0635](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/8cc06351717da1edb2e813f79c1ec84c70ad4d76))
* add Rust toolchain to core image ([61e11d8](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/61e11d8f5d8fc73f8435069a1f7530845572e065))
* **android:** declare the emulator's own X libraries instead of inheriting them ([470f748](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/470f74845752aea9bc36616815e996f1a93d730d))
* **core:** disable VS Code's built-in AI features by default ([6213fa9](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/6213fa9b83c09e7a30ba3325795703ac874dcd0c))
* **core:** install docker buildx, which compose now needs to build at all ([8a848ff](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/8a848fff87f16b487a16d773200bb7b1cae99335))
* **core:** replace host-socket DooD with a nested rootless daemon ([de696f9](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/de696f9a28c22ecf94ca0db01d44a3e5db4e3cbe))
* headless Android emulator support with conditional KVM passthrough ([9f9b051](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/9f9b051851f941e8c9307b58ec0e10b916a4c60c))
* primeira versão do template — setup e start ([0d871bf](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/0d871bf8b48c368ae9b747d9bbf484764bcf0673))
* set file-icons as the default icon theme ([bb5ccb9](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/bb5ccb9e9ce2d36a8ea59c01fb9f40e068403757))


### Bug Fixes

* android stack cmdline-tools download 404 (stale build + wrong path) ([1e62de2](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/1e62de283784cb1776457973c43797399bebb11b))
* android stack SDK not writable, stale build-tools, no NDK ([620c2f0](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/620c2f016d094e37f82fe8e6bc046af13db7fba4))
* **android:** declare libx11-xcb1, which the headless emulator dies without ([4af5b06](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/4af5b065a5d6646a6f47aa6754ac6eb4f7486ee1))
* **android:** install the SDK one package at a time, and with sdkmanager ([de6bc69](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/de6bc690d5549ef62317b5d0daea06d444ee2617))
* **android:** make the SDK actually usable at container runtime ([1e731ff](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/1e731ff908c8196cefb9bb3eef3fd677a1fcdb8e))
* **android:** survive a transient dl.google.com failure instead of dying on it ([076deff](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/076deff463fd8aee0cc676b2f7d78afc69ca010c))
* **ci:** compose stack builds through the same path setup uses ([94ad4c9](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/94ad4c9a0016f7cfdeb34223dfd2a73129eaa0a7))
* **core:** chown the docker config dir, not just the socket dir inside it ([af092b3](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/af092b32de42cb5613ea7debd8d95c81958e3247))
* **core:** raise the container memory cap to 8g, with 2g of swap ([fc9da8a](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/fc9da8a63c40e39029410641df9ebe60e6dd4fd6))
* detect repo root via outermost .git instead of fixed ancestor depth ([9f24a0e](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/9f24a0edb419b1ba86dbddd9a67a58620e5865e1))
* enable clipboard access in code-server webview ([d0db8f4](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/d0db8f464bc92b13881c0d007e086a4d1cafd31b))
* keep the whole Claude Code CLI state in the mounted config dir ([c204aa5](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/c204aa53b140a8fd3e40f28b70c96807fd3c1e2e))
* mitigate garbled accented input in code-server's terminal ([f9cf222](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/f9cf222eaac5c2c5ed54585507fa11936dd13e1e))
* publish code-server's port per-project instead of --network host ([74e2379](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/74e2379a484da84d521a65d7c0713351ba5695c5))
* **python:** skip wheel in get-pip so it stops clobbering deb packaging ([02a8cde](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/02a8cde45e38e5fe95e786221bddefdbed34564b))
* raise container resources and disable swap for android emulator peaks ([9ea210a](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/9ea210a71256b45861c7e9ada68656ab4d0af501))
* relocate android AVD runtime home, migrate off deprecated sdkmanager ([be9dc76](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/be9dc76babe80b67fe5cc549a888e9ea8145abaa))
* stop whiptail menus from showing each option's label twice ([6e3c4d9](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/6e3c4d9011266ffcc21232547750300e80a18dcc))
* work around WebKitGTK dead-key bug breaking accented input ([0987c32](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/0987c32a607ae237ab82cf1c162e3135d6e1d6c2))


### Continuous Integration

* add release-please to manage tags and releases ([565064a](https://github.com/TheHefty/jvsl.env.agents.code-server/commit/565064aba39f9f1841524dac0a6e07493cda6ce5))
