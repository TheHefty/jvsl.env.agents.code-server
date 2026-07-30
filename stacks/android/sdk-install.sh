#!/bin/sh
# Installs exactly one SDK package, with the retry the tooling doesn't have.
#
# Invoked once per package from Dockerfile.frag rather than once for all of
# them, so each package becomes its own image layer. That split is the whole
# point: on a link that intermittently refuses connections, a single atomic
# install of ~5GB is a coin flip that has to come up heads every time, and a
# failure anywhere discards everything already downloaded. Per-package layers
# make progress cumulative instead — a build that dies on the NDK keeps the
# packages that already landed, and the rebuild resumes at the failure rather
# than at the beginning. Measured on the link this was written against:
# ~80% of connects to dl.google.com succeed, which is fine per package and
# hopeless across a single multi-GB one.
set -eu

pkg="$1"
# Top-level directory under $ANDROID_HOME that this package populates. Passed
# in rather than derived, because the chmod below must touch only what this
# package wrote: a blanket `chmod -R a+rX $ANDROID_HOME` would restat every
# previously-installed file, and each layer would then carry its own copy of
# the whole tree — exactly the duplication the per-package split exists to
# avoid.
dir="$2"

# 20 attempts by default, and the number is measured rather than picked.
# Populating this exact package set over this link took 11 passes: the NDK
# landed on its 4th attempt and the system image on its 9th, while the four
# small packages all landed first try. An earlier version of this script
# allowed 5, and a real build duly died on `system-images` at "attempt 5/5"
# after 2219 seconds — with the retry loop describing itself as hardened.
#
# Overridable per RUN (`RUN SDK_INSTALL_ATTEMPTS=40 sdk-install …`) for a
# specific reason worth stating: this file is a build dependency of every
# per-package RUN, so editing it to tune one package invalidates its COPY
# layer and therefore every package layer after it — which is precisely the
# cache the per-package split exists to protect. Tuning through the
# environment moves that edit into a single RUN line, where it invalidates
# only that package and the ones following it. Learned by losing the cache.
#
# The ceiling costs little because most failures here are fast — they die on
# the manifest fetch or a refused connection well short of the timeout — so
# the worst case is dominated by attempts that actually transfer, not by
# 20 x 1200s.
ok=0
for attempt in $(seq 1 "${SDK_INSTALL_ATTEMPTS:-20}"); do
  # `timeout` is load-bearing, not belt-and-braces. sdkmanager retries its
  # manifest fetch internally and *blocks* while doing so — measured here at
  # over 8 minutes with no output and no exit — so without a hard ceiling a
  # bad stretch of network hangs the build instead of failing into this loop
  # where it could actually be retried.
  #
  # `yes` accepts the SDK licence prompts non-interactively; there is no
  # --accept-licences flag on the install path, only the separate
  # `--licenses` mode.
  if yes 2>/dev/null | timeout 1200 sdkmanager --sdk_root="$ANDROID_HOME" "$pkg"; then
    ok=1
    break
  fi
  echo "sdk install failed for '$pkg' (attempt $attempt/${SDK_INSTALL_ATTEMPTS:-20}), retrying in 15s" >&2
  sleep 15
done
# The `ok` flag is load-bearing: a bare `for ... done` exits with the status of
# its last command (the sleep, i.e. 0), which would let an exhausted loop
# report success and bake a half-installed SDK into the image.
[ "$ok" = 1 ]

# Google ships most SDK binaries mode 744, and a build-time `chown` to abc
# would bake in abc's *image* identity (911:1001) only for LinuxServer's init
# to remap it to PUID/PGID at container start — leaving ownership orphaned and
# abc in "other". `a+rX` restores traversal/execution whatever PUID the host
# picks. See the longer note in Dockerfile.frag.
chmod -R a+rX "$ANDROID_HOME/$dir"

# sdkmanager caches the repository manifests it fetched under /root/.android.
# Build-time-only weight: the runtime user is abc, never root.
rm -rf /root/.android/cache
