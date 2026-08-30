# Termux Bootstrap Builder for `com.antigem` (aarch64)

This repository contains an automated build system and GitHub Actions workflow to build custom **Termux Bootstrap archives (`bootstrap-aarch64.zip`)** compiled specifically for Android applications with package name **`com.antigem`**.

---

## 📖 Why a Custom Bootstrap is Required

When creating an Android application (`com.antigem`) that embeds Termux command-line tools:

1. **Android App Sandboxing**: Android assigns every app an isolated Linux user ID (UID) and private directory at `/data/data/<package_name>/files/`.
2. **Hardcoded ELF Paths**: Official Termux packages have paths hardcoded at compile time:
   - Dynamic Linker (`PT_INTERP`): `/data/data/com.termux/files/usr/bin/linker64`
   - Library Search Paths (`DT_RUNPATH`): `/data/data/com.termux/files/usr/lib`
   - Script Shebangs: `#!/data/data/com.termux/files/usr/bin/sh` or `bash`
   - Configuration / Data: `/data/data/com.termux/files/usr/etc`
3. **Linker Failure on Default Binaries**: If you extract standard Termux binaries into `com.antigem`, they will fail with `No such file or directory` or `Permission denied` because the dynamic linker cannot access `/data/data/com.termux`.
4. **Different Character Length**: `com.termux` (10 characters) vs `com.antigem` (11 characters) means simple binary string hex editing corrupts ELF headers.

### The Solution
This repository builds packages from source using the official Termux build engine (`termux-packages`) running inside Docker (`ghcr.io/termux/package-builder`), replacing the target prefix with:
- **`PREFIX`**: `/data/data/com.antigem/files/usr`
- **`HOME`**: `/data/data/com.antigem/files/home`

---

## 📦 What is Included in the Bootstrap

### 1. Full Base System & Package Manager
- **`apt` & `dpkg`**: Full Debian package management suite configured for `com.antigem`.
- **Core Shells**: `bash`, `dash`.
- **Core Utilities**: `coreutils`, `findutils`, `diffutils`, `debianutils`, `gawk`, `grep`, `sed`, `tar`, `gzip`, `bzip2`, `xz-utils`, `unzip`, `util-linux`, `procps`, `psmisc`, `less`, `lsof`, `nano`, `ed`, `patch`, `dos2unix`.
- **Networking & SSL**: `ca-certificates`, `curl`, `net-tools`, `inetutils`, `openssl`, `zlib`.
- **Termux Integration**: `termux-tools`, `termux-exec`, `termux-am`, `termux-keyring`, `termux-licenses`, `command-not-found`.

### 2. Pre-bundled Extra Tools
- **`git`**: Fast version control system compiled for `com.antigem`.
- **`zsh`**: Z shell ready for interactive terminal execution.

---

## 🚀 How to Run the GitHub Workflow

### Option 1: Manual Trigger via GitHub UI (Recommended)
1. Go to your repository on GitHub: `https://github.com/Santoshkurmi/termux-bootstrap`
2. Click on the **Actions** tab.
3. Select the workflow: **Build Custom Termux Bootstrap (com.antigem)**.
4. Click **Run workflow**:
   - **Target CPU architecture**: `aarch64` (default)
   - **Android App Package Name**: `com.antigem` (default)
   - **Bootstrap Type**: `full` (default)
   - **Additional packages**: `git zsh` (default, you can add more e.g. `python nodejs`)
   - **Publish as a GitHub Release**: `true`
5. Click the green **Run workflow** button.

### Option 2: Push to `main`
Any push affecting `.github/workflows/` or `scripts/` will automatically trigger the build pipeline.

### Workflow Outputs
When the workflow completes:
- **`bootstrap-aarch64.zip`**: The ready-to-use Termux bootstrap rootfs archive.
- **`SHA256SUMS.txt`**: Cryptographic checksum for integrity verification.
- **`termux-debs-...`**: All generated `.deb` package files for `com.antigem`.
- **GitHub Release**: Automatically published if enabled.

---

## 📱 Android App Integration Guide (`com.antigem`)

To initialize and execute tools inside your Android app:

### 1. Place or Download the Bootstrap
Place `bootstrap-aarch64.zip` into `app/src/main/assets/` or download it to `context.filesDir` at first launch.

### 2. Kotlin Bootstrap Installer Helper

Create `TermuxInstaller.kt` in your app:

```kotlin
package com.antigem.terminal

import android.content.Context
import android.system.Os
import java.io.*
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream

object TermuxInstaller {

    private const val PACKAGE_NAME = "com.antigem"
    val PREFIX = "/data/data/$PACKAGE_NAME/files/usr"
    val HOME = "/data/data/$PACKAGE_NAME/files/home"

    /**
     * Installs the bootstrap zip into app's private files directory.
     */
    fun setupBootstrap(context: Context, zipInputStream: InputStream, onProgress: (String) -> Unit) {
        val filesDir = context.filesDir // /data/data/com.antigem/files
        val usrDir = File(filesDir, "usr")
        val homeDir = File(filesDir, "home")

        if (!usrDir.exists()) usrDir.mkdirs()
        if (!homeDir.exists()) homeDir.mkdirs()

        onProgress("Extracting bootstrap files...")
        unzip(zipInputStream, filesDir)

        onProgress("Creating symbolic links...")
        processSymlinks(filesDir)

        onProgress("Setting executable permissions...")
        setPermissions(usrDir)

        onProgress("Termux bootstrap installation complete!")
    }

    private fun unzip(inputStream: InputStream, targetDir: File) {
        ZipInputStream(BufferedInputStream(inputStream)).use { zis ->
            var entry: ZipEntry? = zis.nextEntry
            val buffer = ByteArray(8192)
            while (entry != null) {
                val file = File(targetDir, entry.name)
                if (entry.isDirectory) {
                    file.mkdirs()
                } else {
                    file.parentFile?.mkdirs()
                    FileOutputStream(file).use { fos ->
                        var count: Int
                        while (zis.read(buffer).also { count = it } != -1) {
                            fos.write(buffer, 0, count)
                        }
                    }
                }
                entry = zis.nextEntry
            }
        }
    }

    private fun processSymlinks(filesDir: File) {
        val symlinksFile = File(filesDir, "SYMLINKS.txt")
        if (!symlinksFile.exists()) return

        symlinksFile.forEachLine { line ->
            val parts = line.split("←")
            if (parts.size == 2) {
                val target = parts[0].trim()
                var linkPath = parts[1].trim()
                if (linkPath.startsWith("./")) {
                    linkPath = linkPath.substring(2)
                }

                val linkFile = File(filesDir, linkPath)
                linkFile.parentFile?.mkdirs()
                if (linkFile.exists()) linkFile.delete()

                try {
                    Os.symlink(target, linkFile.absolutePath)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
        symlinksFile.delete()
    }

    private fun setPermissions(usrDir: File) {
        val binDir = File(usrDir, "bin")
        val libexecDir = File(usrDir, "libexec")
        val libDir = File(usrDir, "lib")

        binDir.listFiles()?.forEach { it.setExecutable(true, false) }
        libexecDir.listFiles()?.forEach { it.setExecutable(true, false) }
        libDir.listFiles()?.filter { it.name.endsWith(".so") }?.forEach { it.setExecutable(true, false) }
    }

    /**
     * Returns environment variables required to run binaries in com.antigem.
     */
    fun getEnvironment(): Map<String, String> {
        return mapOf(
            "PREFIX" to PREFIX,
            "HOME" to HOME,
            "PATH" to "$PREFIX/bin:$PREFIX/bin/applets",
            "LD_LIBRARY_PATH" to "$PREFIX/lib",
            "TMPDIR" to "$PREFIX/tmp",
            "SHELL" to "$PREFIX/bin/zsh",
            "TERM" to "xterm-256color",
            "LANG" to "en_US.UTF-8"
        )
    }

    /**
     * Executes a command inside the bootstrap environment.
     */
    fun executeCommand(command: List<String>): Process {
        val processBuilder = ProcessBuilder(command)
        val env = processBuilder.environment()
        env.putAll(getEnvironment())
        processBuilder.directory(File(HOME))
        return processBuilder.start()
    }
}
```

### 3. Example: Running `git` or `zsh` from your Android Activity / Service

```kotlin
// Example: Run git clone
val command = listOf(
    "/data/data/com.antigem/files/usr/bin/git",
    "clone",
    "https://github.com/example/repo.git"
)

val process = TermuxInstaller.executeCommand(command)
val output = process.inputStream.bufferedReader().readText()
val exitCode = process.waitFor()
println("Git Exit Code: $exitCode, Output: $output")
```

---

## 🛠️ Adding More Custom Packages

If you need more tools in the bootstrap (e.g., `python`, `nodejs`, `clang`, `sqlite`):
1. In the GitHub Actions **Run workflow** UI, type the package names into the **Additional packages** input:
   ```
   git zsh python nodejs sqlite
   ```
2. Or edit `ADDITIONAL_PACKAGES` in `scripts/build-bootstrap.sh`.

---

## 📜 License
GPLv3 / Apache 2.0 (matching Termux Packages specifications).
# termux-boostrap
# termux-boostrap
