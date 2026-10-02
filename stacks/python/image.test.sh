#!/usr/bin/env bash
# Runs INSIDE a built python-stack image, with no network. Asserts that the
# interpreter the manifest asked for is the one that answers, and — the point of
# the whole task — that something can be **built** against it.
#
# Why that distinction carries the file: this stack stopped installing Debian
# packages and started unpacking a CPython tarball. An interpreter that runs is
# the easy half. `python3 -V` answers perfectly from a build with no headers, no
# libpython and a sysconfig pointing at whatever machine produced it — and the
# failure then arrives as somebody's first `pip install` of anything with C in
# it, which is most of what this stack exists for.
#
# So the load-bearing assertion compiles a C extension, links it, and imports
# it. Everything else here is cheap enough to keep beside it.
#
# Run by .github/workflows/ci.yml's stack-build job, against the image it has
# just built, with this directory mounted read-only at /image-test.
set -uo pipefail

failures=0

check() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1 ($2)"
    else
        echo "FAIL $1"
        echo "     expected: $3"
        echo "     got:      $2"
        failures=$((failures + 1))
    fi
}

# What the composer defaults to with no manifest — the first entry of
# versions.json — which is what CI builds. Read from the file so that adding a
# version cannot make this assert about one nobody builds.
WANT="$(sed -n 's/.*\[[[:space:]]*"\([0-9.]*\)".*/\1/p' /image-test/versions.json)"
[ -n "$WANT" ] || { echo "FAIL could not read the first version from versions.json"; exit 1; }
echo "ok   versions.json's first entry is $WANT"

got="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)"
check "the python3 that answers is the one the manifest asked for" "${got:-none}" "$WANT"

# The pin is only worth something if the build that arrived is the build that
# was pinned. The full version is in standalone.json beside this file.
want_full="$(sed -n "s/.*\"$WANT\"[^}]*\"version\": *\"\([0-9.]*\)\".*/\1/p" /image-test/standalone.json)"
if [ -n "$want_full" ]; then
    got_full="$(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null)"
    check "and it is the exact build pinned in standalone.json" "${got_full:-none}" "$want_full"
else
    echo "FAIL could not read the pinned full version for $WANT from standalone.json"
    failures=$((failures + 1))
fi

# Asked of the interpreter rather than guessed from a path: a standalone build's
# sysconfig is the thing that would be wrong if the archive were laid out
# differently than expected.
inc="$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["include"])' 2>/dev/null)"
check "Python.h is where this interpreter says its headers are" \
    "$([ -n "$inc" ] && [ -f "$inc/Python.h" ] && echo present || echo absent)" "present"

# --- the assertion this file exists for.
work="$(mktemp -d)"
cat > "$work/probe.c" <<'C'
#define PY_SSIZE_T_CLEAN
#include <Python.h>
static PyObject *answer(PyObject *self, PyObject *args) { return PyLong_FromLong(42); }
static PyMethodDef Methods[] = {{"answer", answer, METH_NOARGS, ""}, {NULL, NULL, 0, NULL}};
static struct PyModuleDef mod = {PyModuleDef_HEAD_INIT, "probe", NULL, -1, Methods};
PyMODINIT_FUNC PyInit_probe(void) { return PyModule_Create(&mod); }
C
if cc -shared -fPIC -I"$inc" "$work/probe.c" -o "$work/probe.so" 2>"$work/cc.err"; then
    echo "ok   a C extension compiles and links against this interpreter"
    imported="$(cd "$work" && python3 -c 'import probe; print(probe.answer())' 2>&1)"
    check "and importing it works" "$imported" "42"
else
    echo "FAIL a C extension does not compile against this interpreter — this is the failure a"
    echo "     version check cannot see, and it arrives as somebody's first pip install:"
    sed 's/^/     /' "$work/cc.err"
    failures=$((failures + 1))
fi

# The tarball carries venv and pip; the packages it replaced provided them
# separately, so both are asserted rather than assumed to have come along.
venv_ok="$(python3 -m venv "$work/v" >/dev/null 2>&1 && "$work/v/bin/python" -c 'print("ok")' 2>/dev/null)"
check "python3 -m venv produces a working environment" "${venv_ok:-broken}" "ok"

pip_ok="$(python3 -m pip --version 2>/dev/null | grep -c '^pip ' || true)"
check "pip is present without having been fetched at build time" "$pip_ok" "1"

rm -rf "$work"
echo
echo "python/image.test: $failures failure(s)."
exit "$failures"
