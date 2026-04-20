# SSHFS Mounter for macOS

A native macOS GUI application for mounting SSHFS (SSH File System) volumes.

![Screenshot](native/screenshot.png)

## Features

- **Native macOS app** - Built with Swift/SwiftUI, no Electron overhead
- **Tiny footprint** - Only 1.5MB vs 100MB+ for Electron-based alternatives
- **Dark & Light mode** - Automatically adapts to your system appearance
- **Multiple connections** - Store and manage multiple SSH profiles
- **Quick mount/unmount** - One-click mount and unmount operations
- **SSH key support** - Use password or SSH key authentication
- **Minimal resource usage** - Runs efficiently in the background

## Requirements

- **macOS 13.0 (Ventura) or later** - Also tested on macOS 26.x (Sequoia)
- **sshfs** - Required for mounting remote filesystems

## Installation

### Quick Install (Recommended)

Run the included installation script:

```bash
chmod +x scripts/install-dependencies.sh
./scripts/install-dependencies.sh
```

This will:
1. Install macFUSE (if not already installed)
2. Install sshfs with proper FUSE support
3. Verify library linking

### Manual Install

1. **Install macFUSE:**
   ```bash
   brew install --cask macfuse
   ```

2. **Install sshfs:**
   ```bash
   brew tap gromgit/fuse
   brew install sshfs-mac
   ```

3. **Restart your computer** (required for macFUSE kernel extension to load)

## Fixing libfuse.dylib Errors

If you see an error like:
```
dyld: Library not loaded: libfuse.4.dylib
```

Run the fix script:

```bash
chmod +x scripts/fix-libfuse.sh
./scripts/fix-libfuse.sh
```

This creates the necessary symlinks for the libfuse library.

### Manual Fix

```bash
sudo mkdir -p /usr/local/lib
sudo ln -s /Library/Filesystems/macfuse.fs/Contents/lib/libfuse.2.dylib /usr/local/lib/libfuse.2.dylib
sudo ln -s /Library/Filesystems/macfuse.fs/Contents/lib/libfuse.2.dylib /usr/local/lib/libfuse.4.dylib
```

## Running the Application

### Development

```bash
# Install dependencies
npm install

# Run the application
npm start
```

### Build

```bash
npm run dist
```

The built application will be in the `dist/` directory.

## Usage

1. Click the **+** button to add a new connection
2. Enter your connection details:
   - **Volume title**: A name for this connection
   - **Server**: The SSH server hostname or IP
   - **Port**: SSH port (default: 22)
   - **Username**: Your SSH username
   - **Password** or **Key file**: Authentication method
   - **Remote directory**: Path on the remote server to mount
   - **Mount directory**: Local path where the remote directory will be mounted
3. Click **Save** to store the connection
4. Click **Mount** to mount the remote filesystem
5. Click **Unmount** to disconnect

## Preferences

Preferences are stored in `~/Library/Application Support/sshfs-mounter/config.json`

You can customize:
- Mount command (default: `sshfs`)
- Unmount command (default: `umount`)
- Default mount options

## Troubleshooting

### "Library not loaded: libfuse.4.dylib"

Run the fix script as described above, or manually create the symlinks.

### "sshfs: command not found"

Make sure sshfs is installed and in your PATH:
```bash
which sshfs
```

If not found, reinstall:
```bash
brew install gromgit/fuse/sshfs-mac
```

### Mount point not accessible in Finder

This is a known issue with macOS Sequoia. The mount should still be accessible from the command line.

### Permission denied errors

Make sure the mount directory exists and is writable:
```bash
mkdir -p ~/mnt/myserver
chmod 755 ~/mnt/myserver
```

## License

CC0-1.0 (Public Domain)

## Acknowledgments

- Original project by [iamdroid](https://github.com/i-amdroid/sshfs-mounter)
- Built with [Electron](https://www.electronjs.org/)
- Uses [sshfs](https://github.com/libfuse/sshfs) and [macFUSE](https://macfuse.github.io/)
