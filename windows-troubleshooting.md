# DevEnv Windows Troubleshooting Guide

This guide addresses common issues you might encounter when using DevEnv with Windows and WSL.

## WSL Installation Issues

### Problem: "WSL 2 requires an update to its kernel component"

**Symptoms**: When trying to use WSL, you get an error about requiring a kernel update.

**Solution**: 
1. Download and install the [WSL 2 Linux kernel update package](https://aka.ms/wsl2kernel)
2. Run `wsl --set-default-version 2` in PowerShell or Command Prompt
3. Restart your system if needed

### Problem: "Virtual Machine Platform" not enabled

**Symptoms**: WSL installation fails with an error about Virtual Machine Platform.

**Solution**:
1. Open PowerShell as Administrator
2. Run: `dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart`
3. Run: `dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart`
4. Restart your computer
5. Continue with WSL installation

### Problem: Virtualization not enabled in BIOS/UEFI

**Symptoms**: WSL fails to start with errors about virtualization.

**Solution**:
1. Restart your computer and enter BIOS/UEFI settings (typically by pressing F2, Del, or F12 during startup)
2. Find the virtualization setting (may be called VT-x, AMD-V, SVM, or Virtualization Technology)
3. Enable the setting
4. Save and exit BIOS/UEFI
5. Retry WSL installation

## Performance Issues

### Problem: Slow file system performance in mounted Windows drives

**Symptoms**: Operations on files in `/mnt/c` or other Windows drives are very slow.

**Solutions**:

1. **Keep project files in the Linux file system**:
   ```bash
   # Move projects to Linux file system
   mkdir -p ~/Projects
   cp -r /mnt/c/Projects/* ~/Projects/
   ```

2. **Optimize WSL configuration**:
   ```powershell
   # Create or edit .wslconfig in your Windows user directory
   notepad $env:USERPROFILE\.wslconfig
   ```
   
   Add the following:
   ```
   [wsl2]
   memory=8GB
   processors=4
   swap=4GB
   ```

3. **Use Windows Terminal** instead of Command Prompt or PowerShell for WSL.

### Problem: High memory or CPU usage

**Symptoms**: WSL is using too much system resources.

**Solution**:
1. Edit `.wslconfig` to limit resource usage:
   ```
   [wsl2]
   memory=4GB
   processors=2
   ```
2. Restart WSL with: `wsl --shutdown` and then start again

## Docker Integration Issues

### Problem: Docker Desktop not detected

**Symptoms**: DevEnv reports that Docker Desktop is not installed or detected.

**Solution**:
1. Install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)
2. During installation, ensure "Use WSL 2 based engine" is checked
3. After installation, open Docker Desktop settings and ensure "WSL Integration" is enabled for your distribution
4. Restart WSL with: `wsl --shutdown` and then start again

### Problem: "Cannot connect to the Docker daemon"

**Symptoms**: Commands like `docker ps` fail with a daemon connection error.

**Solutions**:

1. **Start Docker Desktop**:
   ```bash
   # Use the DevEnv alias
   dstart
   
   # Or manually start from Windows
   powershell.exe "Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'"
   ```

2. **Wait for Docker Desktop to fully start** (can take up to a minute)

3. **Check Docker Desktop settings**:
   - Open Docker Desktop
   - Go to Settings > Resources > WSL Integration
   - Ensure your distribution is enabled

4. **Configure environment variables**:
   ```bash
   echo 'export DOCKER_HOST=tcp://localhost:2375' >> ~/.bashrc
   source ~/.bashrc
   ```

## VS Code Integration Issues

### Problem: Remote-WSL extension not working

**Symptoms**: VS Code doesn't show the remote connection or fails to connect to WSL.

**Solutions**:

1. **Install or update the Remote-WSL extension**:
   ```bash
   # Use the DevEnv script
   ~/.devenv/windows_scripts/vscode_wsl.sh install-extension
   ```

2. **Check VS Code installation in Windows**:
   - Ensure VS Code is installed in Windows, not just in WSL
   - Typical installation path: `C:\Program Files\Microsoft VS Code`

3. **Reinstall VS Code server in WSL**:
   ```bash
   # Remove existing server files
   rm -rf ~/.vscode-server
   
   # Reinstall server components
   ~/.devenv/windows_scripts/vscode_wsl.sh install-server
   ```

4. **Check WSL version**:
   ```powershell
   # Run in PowerShell
   wsl --status
   ```
   Make sure it shows WSL 2 as the default version

### Problem: File changes not detected in VS Code

**Symptoms**: Changes made to files in WSL don't automatically appear in VS Code.

**Solution**:
1. Enable polling for file watching in VS Code settings:
   ```json
   "remote.WSL.fileWatcher.polling": true,
   "remote.WSL.fileWatcher.pollingInterval": 5000
   ```
2. These settings should be automatically applied by DevEnv, but you can check by opening VS Code settings and searching for "WSL"

## Path and File System Issues

### Problem: Windows paths not working in WSL

**Symptoms**: Windows file paths like `C:\Users\name` don't work in WSL commands.

**Solutions**:

1. **Convert Windows paths to WSL format**:
   - Windows path: `C:\Users\name\Documents`
   - WSL path: `/mnt/c/Users/name/Documents`

2. **Use the `wslpath` tool**:
   ```bash
   # Convert Windows path to WSL path
   wslpath 'C:\Users\name\Documents'
   
   # Convert WSL path to Windows path
   wslpath -w '/mnt/c/Users/name/Documents'
   ```

3. **Use DevEnv aliases**:
   ```bash
   # Go to Windows home directory
   cdwin
   
   # Go to Projects directory
   cdproj
   ```

### Problem: File permission issues

**Symptoms**: Permission denied errors when trying to access or modify files.

**Solutions**:

1. **For Windows files**: 
   - WSL mounts Windows drives with specific permissions by default
   - The DevEnv WSL module configures optimal mount options
   - Restart WSL to apply changes: `wsl --shutdown` and start again

2. **For Linux files**:
   - Use standard Linux permissions commands
   ```bash
   chmod +x myfile.sh
   chown user:user myfile
   ```

## Shell and Terminal Issues

### Problem: Font issues in terminal

**Symptoms**: Special characters or icons don't display correctly.

**Solution**:
1. Install the recommended fonts:
   ```bash
   # Install fonts if not done during setup
   ~/.devenv/devenv.sh install zsh --force
   ```

2. Configure Windows Terminal to use the font:
   - Open Windows Terminal settings (Ctrl+, or click on the dropdown and select Settings)
   - Go to your WSL profile
   - Set "Font face" to "MesloLGS NF" or another Nerd Font

### Problem: ZSH not working correctly

**Symptoms**: Prompt looks wrong, aliases missing, or other ZSH issues.

**Solutions**:

1. **Reinstall ZSH configuration**:
   ```bash
   ~/.devenv/devenv.sh install zsh --force
   ```

2. **Source configuration**:
   ```bash
   source ~/.zshrc
   ```

3. **Check if ZSH is the default shell**:
   ```bash
   echo $SHELL
   # Should return /bin/zsh
   ```

4. **Make ZSH the default shell if needed**:
   ```bash
   chsh -s $(which zsh)
   ```

## Windows Terminal Issues

### Problem: Windows Terminal profile missing

**Symptoms**: No DevEnv profile in Windows Terminal dropdown.

**Solutions**:

1. **Manually add profile**:
   - Open Windows Terminal settings (JSON file)
   - Add a new profile:
   ```json
   {
       "name": "DevEnv (WSL)",
       "commandline": "wsl.exe -d Ubuntu-20.04",
       "startingDirectory": "//wsl$/Ubuntu-20.04/home/your-username",
       "icon": "%USERPROFILE%\\.devenv\\icons\\devenv.png",
       "fontFace": "MesloLGS NF"
   }
   ```

2. **Run the WSL setup again**:
   ```bash
   ~/.devenv/devenv.sh install wsl --force
   ```

### Problem: Windows Terminal crashes when opening WSL

**Symptoms**: Windows Terminal closes immediately when trying to open the WSL tab.

**Solutions**:

1. **Run WSL directly first**:
   - Open Command Prompt
   - Run `wsl` to enter WSL
   - If that works, try Windows Terminal again

2. **Fix WSL installation**:
   - Open PowerShell as Administrator
   - Run `wsl --shutdown`
   - Run `wsl --unregister Ubuntu-20.04` (use your distribution name)
   - Run `wsl --install -d Ubuntu-20.04`

## DevEnv Module Issues

### Problem: Module installation fails

**Symptoms**: DevEnv module installation fails with errors.

**Solutions**:

1. **Check the logs**:
   ```bash
   cat ~/.devenv/logs/devenv_latest.log
   ```

2. **Try forcing installation**:
   ```bash
   ~/.devenv/devenv.sh install <module> --force
   ```

3. **Verify dependencies**:
   - Make sure all required packages are installed
   - For example, for Docker module:
   ```bash
   sudo apt-get update
   sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
   ```

### Problem: Module not working after installation

**Symptoms**: Module shows as installed but functionality doesn't work.

**Solution**:
1. Verify the module:
   ```bash
   ~/.devenv/devenv.sh verify <module>
   ```

2. Check module logs:
   ```bash
   cat ~/.devenv/logs/<module>_latest.log
   ```

3. Reinstall with force option:
   ```bash
   ~/.devenv/devenv.sh install <module> --force
   ```

## System-Wide Issues

### Problem: WSL uses too much disk space

**Symptoms**: WSL virtual disk file (ext4.vhdx) grows very large.

**Solutions**:

1. **Compact the WSL virtual disk**:
   ```powershell
   # In PowerShell as Administrator
   wsl --shutdown
   diskpart
   # In diskpart:
   select vdisk file="C:\Users\YourUsername\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc\LocalState\ext4.vhdx"
   attach vdisk readonly
   compact vdisk
   detach vdisk
   exit
   ```

2. **Clean up unnecessary files in WSL**:
   ```bash
   # Clear apt cache
   sudo apt-get clean
   
   # Remove old kernels
   sudo apt-get autoremove
   
   # Clean Docker (if installed)
   docker system prune -a
   ```

### Problem: WSL restart required

**Symptoms**: Changes to WSL configuration not taking effect.

**Solution**:
1. Shutdown WSL:
   ```powershell
   # In PowerShell
   wsl --shutdown
   ```

2. Restart Windows Terminal or open a new session

## Getting More Help

If you continue to experience issues:

1. Check the DevEnv documentation: https://github.com/yourusername/devenv/wiki

2. Open an issue on GitHub: https://github.com/yourusername/devenv/issues/new

3. Review Microsoft's WSL troubleshooting guide: https://docs.microsoft.com/en-us/windows/wsl/troubleshooting

4. For Docker issues, see: https://docs.docker.com/desktop/windows/troubleshoot/