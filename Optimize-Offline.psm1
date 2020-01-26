﻿Using module .\Src\Offline-Resources.psm1
#Requires -RunAsAdministrator
#Requires -Version 5
#Requires -Module Dism
<#
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2019 v5.7.172
	 Created on:   	11/20/2019 11:53 AM
	 Created by:   	BenTheGreat
	 Filename:     	Optimize-Offline.psm1
	 Version:       4.0.0.4
	 Last updated:	01/25/2020
	-------------------------------------------------------------------------
	 Module Name: Optimize-Offline
	===========================================================================
#>
Function Optimize-Offline
{
	<#
	.EXTERNALHELP Optimize-Offline-help.xml
	#>

	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory = $true,
			HelpMessage = 'The path to a Windows 10 Installation Media ISO, Windows 10 WIM or Windows 10 ESD file.')]
		[ValidateScript( {
				If ($PSItem.Exists -and $PSItem.Extension -eq '.ISO' -or $PSItem.Extension -eq '.WIM' -or $PSItem.Extension -eq '.ESD') { $PSItem.FullName }
				Else { Throw ('Invalid source path: "{0}"' -f $PSItem.FullName) }
			})]
		[IO.FileInfo]$SourcePath,
		[Parameter(Mandatory = $false,
			HelpMessage = 'Selectively or automatically deprovisions Windows Apps and removes their associated provisioning packages (.appx or .appxbundle).')]
		[ValidateSet('Select', 'Whitelist', 'All')]
		[String]$WindowsApps,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of System Apps for selective removal.')]
		[Switch]$SystemApps,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of Capability Packages for selective removal.')]
		[Switch]$Capabilities,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of Windows Cabinet File Packages for selective removal.')]
		[Switch]$Packages,
		[Parameter(HelpMessage = 'Populates and outputs a Gridview list of Windows Optional Features for selective disabling and enabling.')]
		[Switch]$Features,
		[Parameter(HelpMessage = 'Integrates the Developer Mode Feature into the image.')]
		[Switch]$DeveloperMode,
		[Parameter(HelpMessage = 'Integrates the Microsoft Windows Store and its required dependencies into the image.')]
		[Switch]$WindowsStore,
		[Parameter(HelpMessage = 'Integrates the Microsoft Edge Browser into the image.')]
		[Switch]$MicrosoftEdge,
		[Parameter(HelpMessage = 'Integrates the traditional Win32 Calculator into the image.')]
		[Switch]$Win32Calc,
		[Parameter(HelpMessage = 'Integrates the Windows Server Data Deduplication Feature into the image.')]
		[Switch]$Dedup,
		[Parameter(Mandatory = $false,
			HelpMessage = 'Integrates the Microsoft Diagnostic and Recovery Toolset (DaRT 10) and Windows 10 Debugging Tools into Windows Setup and Windows Recovery.')]
		[ValidateSet('Setup', 'Recovery', 'All')]
		[String]$DaRT,
		[Parameter(HelpMessage = 'Applies optimized settings to the image registry hives.')]
		[Switch]$Registry,
		[Parameter(Mandatory = $false,
			HelpMessage = 'Integrates user-specific content added to the "Content/Additional" directory into the image when enabled within the hashtable.')]
		[Hashtable]$Additional = @{ $Setup = $false; $Wallpaper = $false; $SystemLogo = $false; $LockScreen = $false; $RegistryTemplates = $false; $Unattend = $false; $Drivers = $false; $NetFx3 = $false },
		[Parameter(Mandatory = $false,
			HelpMessage = 'Creates a new bootable Windows Installation Media ISO.')]
		[ValidateSet('Prompt', 'No-Prompt')]
		[String]$ISO
	)

	Begin
	{
		#region Set Local Variables
		$Global:DefaultVariables = (Get-Variable).Name
		$Global:DefaultErrorActionPreference = $ErrorActionPreference
		$ProgressPreference = 'SilentlyContinue'
		$Host.UI.RawUI.BackgroundColor = 'Black'; Clear-Host
		#endregion Set Local Variables

		#region Import Localized Data
		Try { Import-LocalizedData -BindingVariable OptimizedData -FileName Optimize-Offline.strings.psd1 -ErrorAction Stop }
		Catch { Write-Warning ('Failed to import the localized data file: "{0}"' -f (GetPath -Path $OptimizeOffline.LocalizedDataStrings -Split Leaf)); Break }
		#endregion Import Localized Data
	}
	Process
	{
		#region Create the Working File Structure
		Test-Requirements

		If (Get-WindowsImage -Mounted)
		{
			$Host.UI.RawUI.WindowTitle = $OptimizedData.ActiveMountPoints
			Write-Host $OptimizedData.ActiveMountPoints -ForegroundColor Cyan
			Dismount-Images; Clear-Host
		}

		Try
		{
			$Timer = New-Object -TypeName System.Diagnostics.Stopwatch -ErrorAction SilentlyContinue
			@(Get-ChildItem -Path $OptimizeOffline.Directory -Filter OfflineTemp_* -Directory), (GetPath -Path $Env:SystemRoot -Child 'Logs\DISM\dism.log') | Purge -ErrorAction Ignore
			Set-Location -Path $OptimizeOffline.Directory
			[Environment]::CurrentDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
			@($TempDirectory, $ImageFolder, $WorkFolder, $ScratchFolder, $LogFolder) | Create -ErrorAction Stop
			[Void](Clear-WindowsCorruptMountPoint)
		}
		Catch
		{
			Write-Warning $OptimizedData.FailedToCreateWorkingFileStructure
			Get-ChildItem -Path $OptimizeOffline.Directory -Filter OfflineTemp_* -Directory | Purge -ErrorAction SilentlyContinue
			Break
		}
		#endregion Create the Working File Structure

		#region Media Export
		If ($SourcePath.Extension -eq '.ISO')
		{
			$ISOMount = (Mount-DiskImage -ImagePath $SourcePath.FullName -StorageType ISO -PassThru | Get-Volume).DriveLetter + ':'
			[Void](Get-PSDrive)
			If (Get-ChildItem -Path (GetPath -Path $ISOMount -Child sources) -Filter install.* -File)
			{
				$Host.UI.RawUI.WindowTitle = ($OptimizedData.ExportingMedia -f $SourcePath.Name)
				Write-Host ($OptimizedData.ExportingMedia -f $SourcePath.Name) -ForegroundColor Cyan
				$ISOMedia = Create -Path (GetPath -Path $TempDirectory -Child $SourcePath.BaseName) -PassThru
				$ISOMedia | Export-DataFile -File ISOMedia
				ForEach ($Item In Get-ChildItem -Path $ISOMount -Recurse)
				{
					$ISOExport = $ISOMedia.FullName + $Item.FullName.Replace($ISOMount, $null)
					Copy-Item -Path $Item.FullName -Destination $ISOExport
				}
				Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child sources) -Include install.*, boot.wim -File -Recurse | Move-Item -Destination $ImageFolder -PassThru | Set-ItemProperty -Name IsReadOnly -Value $false
				$InstallWim = Get-ChildItem -Path $ImageFolder -Filter install.* | Select-Object -ExpandProperty FullName
				If ([IO.Path]::GetExtension($InstallWim) -eq '.ESD') { $DynamicParams.ESD = $true }
				$BootWim = Get-ChildItem -Path $ImageFolder -Filter boot.wim | Select-Object -ExpandProperty FullName
				If ($BootWim) { $DynamicParams.Boot = $true }
				Do
				{
					[Void](Dismount-DiskImage -ImagePath $SourcePath.FullName)
				}
				While ((Get-DiskImage -ImagePath $SourcePath.FullName).Attached -eq $true)
			}
			Else
			{
				Write-Warning ($OptimizedData.InvalidWindowsInstallMedia -f $SourcePath.Name)
				Do
				{
					[Void](Dismount-DiskImage -ImagePath $SourcePath.FullName)
				}
				While ((Get-DiskImage -ImagePath $SourcePath.FullName).Attached -eq $true)
				$TempDirectory | Purge -ErrorAction SilentlyContinue
				Break
			}
		}
		ElseIf ($SourcePath.Extension -eq '.WIM' -or $SourcePath.Extension -eq '.ESD')
		{
			$Host.UI.RawUI.WindowTitle = ($OptimizedData.CopyingImage -f $SourcePath.Extension.TrimStart('.').ToUpper(), $SourcePath.DirectoryName)
			Write-Host ($OptimizedData.CopyingImage -f $SourcePath.Extension.TrimStart('.').ToUpper(), $SourcePath.DirectoryName) -ForegroundColor Cyan
			If ($SourcePath.Extension -eq '.ESD') { $DynamicParams.ESD = $true }
			Copy-Item -Path $SourcePath.FullName -Destination $ImageFolder
			Get-ChildItem -Path $ImageFolder -Filter $SourcePath.Name | Rename-Item -NewName ('install' + $SourcePath.Extension) -PassThru | Set-ItemProperty -Name IsReadOnly -Value $false
			$InstallWim = Get-ChildItem -Path $ImageFolder -Filter install.* | Select-Object -ExpandProperty FullName
			If ($ISO) { Remove-Variable -Name ISO }
		}
		#endregion Media Export

		#region Image and Metadata Validation
		If ((Get-WindowsImage -ImagePath $InstallWim).Count -gt 1)
		{
			Do
			{
				$Host.UI.RawUI.WindowTitle = $OptimizedData.SelectWindowsEdition
				$EditionList = Get-WindowsImage -ImagePath $InstallWim | Select-Object -Property @{ Label = 'Index'; Expression = { ($PSItem.ImageIndex) } }, @{ Label = 'Name'; Expression = { ($PSItem.ImageName) } }, @{ Label = 'Size (GB)'; Expression = { '{0:N2}' -f ($PSItem.ImageSize / 1GB) } } | Out-GridView -Title "Select the Windows 10 Edition to Optimize." -OutputMode Single
				$ImageIndex = $EditionList.Index
			}
			While ($EditionList.Length -eq 0)
			$Host.UI.RawUI.WindowTitle = $null
		}
		Else { $ImageIndex = 1 }

		Try
		{
			$InstallInfo = $InstallWim | Get-ImageData -Index $ImageIndex -ErrorAction Stop
		}
		Catch
		{
			Write-Warning ($OptimizedData.FailedToRetrieveImageMetadata -f (GetPath -Path $InstallWim -Split Leaf))
			$TempDirectory | Purge -ErrorAction SilentlyContinue
			Break
		}

		If (!$InstallInfo.Version.StartsWith(10))
		{
			Write-Warning ($OptimizedData.UnsupportedImageVersion -f $InstallInfo.Version)
			$TempDirectory | Purge -ErrorAction SilentlyContinue
			Break
		}

		If ($InstallInfo.Architecture -ne 'amd64')
		{
			Write-Warning ($OptimizedData.UnsupportedImageArch -f $InstallInfo.Architecture)
			$TempDirectory | Purge -ErrorAction SilentlyContinue
			Break
		}

		If ($InstallInfo.InstallationType.Contains('Server') -or $InstallInfo.InstallationType.Contains('WindowsPE'))
		{
			Write-Warning ($OptimizedData.UnsupportedImageType -f $InstallInfo.InstallationType)
			$TempDirectory | Purge -ErrorAction SilentlyContinue
			Break
		}

		If ($InstallInfo.Build -ge '17134' -and $InstallInfo.Build -le '18362')
		{
			If ($InstallInfo.Build -eq '18362' -and $InstallInfo.Language -ne 'en-US' -and $MicrosoftEdge.IsPresent) { $MicrosoftEdge = $false }
			If ($InstallInfo.Build -lt '17763' -and $MicrosoftEdge.IsPresent) { $MicrosoftEdge = $false }
			If ($InstallInfo.Build -eq '17134' -and $DeveloperMode.IsPresent) { $DeveloperMode = $false }
			If ($InstallInfo.Language -ne 'en-US' -and $Win32Calc.IsPresent) { $Win32Calc = $false }
			If ($InstallInfo.Build -gt '17134' -and $InstallInfo.Language -ne 'en-US' -and $Dedup.IsPresent) { $Dedup = $false }
			If ($InstallInfo.Language -ne 'en-US' -and $DaRT) { Remove-Variable -Name DaRT }
			If ($InstallInfo.Name -like "*LTSC*")
			{
				$DynamicParams.LTSC = $true
				If ($WindowsApps) { Remove-Variable -Name WindowsApps }
				If ($Win32Calc.IsPresent) { $Win32Calc = $false }
			}
			Else
			{
				If ($WindowsStore.IsPresent) { $WindowsStore = $false }
				If ($MicrosoftEdge.IsPresent) { $MicrosoftEdge = $false }
			}
		}
		Else
		{
			Write-Warning ($OptimizedData.UnsupportedImageBuild -f $InstallInfo.Build)
			$TempDirectory | Purge -ErrorAction SilentlyContinue
			Break
		}
		#endregion Image and Metadata Validation

		#region Image Preparation
		If ($DynamicParams.ESD)
		{
			Try
			{
				$ExportToWimParams = @{
					SourceImagePath      = $InstallWim
					SourceIndex          = $ImageIndex
					DestinationImagePath = '{0}\install.wim' -f $WorkFolder
					CompressionType      = 'Maximum'
					CheckIntegrity       = $true
					ScratchDirectory     = $ScratchFolder
					LogPath              = $DISMLog
					ErrorAction          = 'Stop'
				}
				$Host.UI.RawUI.WindowTitle = ($OptimizedData.ExportingInstallToWim -f (GetPath -Path $InstallWim -Split Leaf), (GetPath -Path ([IO.Path]::ChangeExtension($InstallWim, '.wim')) -Split Leaf))
				Write-Host ($OptimizedData.ExportingInstallToWim -f (GetPath -Path $InstallWim -Split Leaf), (GetPath -Path ([IO.Path]::ChangeExtension($InstallWim, '.wim')) -Split Leaf)) -ForegroundColor Cyan
				[Void](Export-WindowsImage @ExportToWimParams)
				$InstallWim | Purge -ErrorAction SilentlyContinue
				$InstallWim = Get-ChildItem -Path $WorkFolder -Filter install.wim | Move-Item -Destination $ImageFolder -Force -PassThru | Select-Object -ExpandProperty FullName
				If ($ImageIndex -ne 1) { $ImageIndex = 1 }
			}
			Catch
			{
				Write-Warning ($OptimizedData.FailedExportingInstallToWim -f (GetPath -Path $InstallWim -Split Leaf), (GetPath -Path ([IO.Path]::ChangeExtension($InstallWim, '.wim')) -Split Leaf))
				$TempDirectory | Purge -ErrorAction SilentlyContinue
				Break
			}
		}

		Try
		{
			Log -Info ($OptimizedData.SupportedImageBuild -f $InstallInfo.Build)
			Start-Sleep 3; $Timer.Start(); $Error.Clear()
			$InstallMount | Create -ErrorAction Stop
			$MountInstallParams = @{
				ImagePath        = $InstallWim
				Index            = $ImageIndex
				Path             = $InstallMount
				ScratchDirectory = $ScratchFolder
				LogPath          = $DISMLog
				ErrorAction      = 'Stop'
			}
			Log -Info ($OptimizedData.MountingImage -f $InstallInfo.Name)
			[Void](Mount-WindowsImage @MountInstallParams)
			RegHives -Load
			Get-ItemProperty -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue | Export-DataFile -File CurrentVersion -ErrorAction SilentlyContinue
			RegHives -Unload
		}
		Catch
		{
			Log -Error ($OptimizedData.FailedMountingImage -f $InstallInfo.Name)
			$OptimizeErrors.Add($Error[0])
			Stop-Optimize
		}

		If (Test-Path -Path (GetPath -Path $InstallMount -Child 'Windows\System32\Recovery\winre.wim'))
		{
			$WinREPath = GetPath -Path $InstallMount -Child 'Windows\System32\Recovery\winre.wim'
			Copy-Item -Path $WinREPath -Destination $ImageFolder -Force
			$RecoveryWim = Get-ChildItem -Path $ImageFolder -Filter winre.wim | Select-Object -ExpandProperty FullName
			$DynamicParams.Recovery = $true
		}

		If ($DynamicParams.Boot)
		{
			Try
			{
				$BootInfo = $BootWim | Get-ImageData -Index 2 -ErrorAction Stop
			}
			Catch
			{
				Log -Error ($OptimizedData.FailedToRetrieveImageMetadata -f (GetPath -Path $BootWim -Split Leaf))
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
		}

		If ($BootInfo)
		{
			Try
			{
				$BootMount | Create -ErrorAction Stop
				$MountBootParams = @{
					Path             = $BootMount
					ImagePath        = $BootWim
					Index            = 2
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					ErrorAction      = 'Stop'
				}
				Log -Info ($OptimizedData.MountingImage -f $BootInfo.Name)
				[Void](Mount-WindowsImage @MountBootParams)
			}
			Catch
			{
				Log -Error ($OptimizedData.FailedMountingImage -f $BootInfo.Name)
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
		}

		If ($DynamicParams.Recovery)
		{
			Try
			{
				$RecoveryInfo = $RecoveryWim | Get-ImageData -Index 1 -ErrorAction Stop
			}
			Catch
			{
				Log -Error ($OptimizedData.FailedToRetrieveImageMetadata -f (GetPath -Path $RecoveryWim -Split Leaf))
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
		}

		If ($RecoveryInfo)
		{
			Try
			{
				$RecoveryMount | Create -ErrorAction Stop
				$MountRecoveryParams = @{
					Path             = $RecoveryMount
					ImagePath        = $RecoveryWim
					Index            = 1
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					ErrorAction      = 'Stop'
				}
				Log -Info ($OptimizedData.MountingImage -f $RecoveryInfo.Name)
				[Void](Mount-WindowsImage @MountRecoveryParams)
			}
			Catch
			{
				Log -Error ($OptimizedData.FailedMountingImage -f $RecoveryInfo.Name)
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
		}

		If ((Repair-WindowsImage -Path $InstallMount -CheckHealth).ImageHealthState -eq 'Healthy')
		{
			Log -Info $OptimizedData.PreOptimizedImageHealthHealthy
			Start-Sleep 3; Clear-Host
		}
		Else
		{
			Log -Error $OptimizedData.PreOptimizedImageHealthCorrupted
			Stop-Optimize
		}
		#endregion Image Preparation

		#region Provisioned App Package Removal
		If ($WindowsApps -and (Get-AppxProvisionedPackage -Path $InstallMount).Count -gt 0)
		{
			$Host.UI.RawUI.WindowTitle = "Remove Provisioned App Packages."
			$AppxPackages = Get-AppxProvisionedPackage -Path $InstallMount | Select-Object -Property DisplayName, PackageName | Sort-Object -Property DisplayName
			$RemovedAppxPackages = [Collections.Hashtable]::New()
			Switch ($PSBoundParameters.WindowsApps)
			{
				'Select'
				{
					Try
					{
						$AppxPackages | Out-GridView -Title "Select the Provisioned App Packages to Remove." -PassThru | ForEach-Object -Process {
							$RemoveAppxParams = @{
								Path             = $InstallMount
								PackageName      = $PSItem.PackageName
								ScratchDirectory = $ScratchFolder
								LogPath          = $DISMLog
								ErrorAction      = 'Stop'
							}
							Log -Info ($OptimizedData.RemovingWindowsApp -f $PSItem.DisplayName)
							[Void](Remove-AppxProvisionedPackage @RemoveAppxParams)
							$RemovedAppxPackages.Add($PSItem.DisplayName, $PSItem.PackageName)
						}
						$DynamicParams.WindowsApps = $true
					}
					Catch
					{
						Log -Error $OptimizedData.FailedRemovingWindowsApps
						$OptimizeErrors.Add($Error[0])
						Stop-Optimize
					}
					Break
				}
				'Whitelist'
				{
					If (Test-Path -Path $OptimizeOffline.AppxWhitelist)
					{
						Try
						{
							$WhitelistJSON = Get-Content -Path $OptimizeOffline.AppxWhitelist -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
							$AppxPackages | ForEach-Object -Process {
								If ($PSItem.DisplayName -notin $WhitelistJSON.DisplayName)
								{
									$RemoveAppxParams = @{
										Path             = $InstallMount
										PackageName      = $PSItem.PackageName
										ScratchDirectory = $ScratchFolder
										LogPath          = $DISMLog
										ErrorAction      = 'Stop'
									}
									Log -Info ($OptimizedData.RemovingWindowsApp -f $PSItem.DisplayName)
									[Void](Remove-AppxProvisionedPackage @RemoveAppxParams)
									$RemovedAppxPackages.Add($PSItem.DisplayName, $PSItem.PackageName)
								}
							}
							$DynamicParams.WindowsApps = $true
						}
						Catch
						{
							Log -Error $OptimizedData.FailedRemovingWindowsApps
							$OptimizeErrors.Add($Error[0])
							Stop-Optimize
						}
					}
					Break
				}
				'All'
				{
					Try
					{
						$AppxPackages | ForEach-Object -Process {
							$RemoveAppxParams = @{
								Path             = $InstallMount
								PackageName      = $PSItem.PackageName
								ScratchDirectory = $ScratchFolder
								LogPath          = $DISMLog
								ErrorAction      = 'Stop'
							}
							Log -Info ($OptimizedData.RemovingWindowsApp -f $PSItem.DisplayName)
							[Void](Remove-AppxProvisionedPackage @RemoveAppxParams)
							$RemovedAppxPackages.Add($PSItem.DisplayName, $PSItem.PackageName)
						}
						$DynamicParams.WindowsApps = $true
					}
					Catch
					{
						Log -Error $OptimizedData.FailedRemovingWindowsApps
						$OptimizeErrors.Add($Error[0])
						Stop-Optimize
					}
					Break
				}
			}
			$Host.UI.RawUI.WindowTitle = $null; Clear-Host
		}
		#endregion Provisioned App Package Removal

		#region System App Removal
		If ($SystemApps.IsPresent)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Remove System Apps."
			Write-Warning $OptimizedData.SystemAppsWarning
			Start-Sleep 5
			$InboxAppsKey = "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\InboxApplications"
			RegHives -Load
			$InboxAppsPackages = Get-ChildItem -Path $InboxAppsKey -Name | ForEach-Object -Process {
				$Name = $PSItem.Split('_')[0]; $PackageName = $PSItem
				If ($Name -like '1527c705-839a-4832-9118-54d4Bd6a0c89') { $Name = 'Microsoft.Windows.FilePicker' }
				If ($Name -like 'c5e2524a-ea46-4f67-841f-6a9465d9d515') { $Name = 'Microsoft.Windows.FileExplorer' }
				If ($Name -like 'E2A4F912-2574-4A75-9BB0-0D023378592B') { $Name = 'Microsoft.Windows.AppResolverUX' }
				If ($Name -like 'F46D4000-FD22-4DB4-AC8E-4E1DDDE828FE') { $Name = 'Microsoft.Windows.AddSuggestedFoldersToLibarayDialog' }
				[PSCustomObject]@{ Name = $Name; PackageName = $PackageName }
			} | Sort-Object -Property Name | Out-GridView -Title "Remove System Apps." -PassThru
			If ($InboxAppsPackages)
			{
				Clear-Host
				$RemovedSystemApps = [Collections.Hashtable]::New()
				Try
				{
					$InboxAppsPackages | ForEach-Object -Process {
						$PackageKey = (GetPath -Path $InboxAppsKey -Child $PSItem.PackageName) -replace 'HKLM:', 'HKLM'
						Log -Info ($OptimizedData.RemovingSystemApp -f $PSItem.Name)
						$RET = StartExe $REG -Arguments ('DELETE "{0}" /F' -f $PackageKey) -ErrorAction Stop
						If ($RET -eq 1) { Log -Error ($OptimizedData.FailedRemovingSystemApp -f $PSItem.Name); Return }
						$RemovedSystemApps.Add($PSItem.Name, $PSItem.PackageName)
						Start-Sleep 2
					}
					$DynamicParams.SystemApps = $true
				}
				Catch
				{
					Log -Error $OptimizedData.FailedRemovingSystemApps
					$OptimizeErrors.Add($Error[0])
					Stop-Optimize
				}
				Finally
				{
					RegHives -Unload
				}
			}
			$Host.UI.RawUI.WindowTitle = $null; Clear-Host
		}
		#endregion System App Removal

		#region Removed Package Clean-up
		If ($DynamicParams.WindowsApps -or $DynamicParams.SystemApps)
		{
			Log -Info $OptimizedData.RemovedPackageCleanup
			If ($DynamicParams.WindowsApps)
			{
				If ((Get-AppxProvisionedPackage -Path $InstallMount).Count -eq 0) { Get-ChildItem -Path (GetPath -Path $InstallMount -Child 'Program Files\WindowsApps') -Force | Purge -Force }
				Else { Get-ChildItem -Path (GetPath -Path $InstallMount -Child 'Program Files\WindowsApps') -Force | Where-Object -Property Name -In $RemovedAppxPackages.Values | Purge -Force }
			}
			Try
			{
				RegHives -Load
				$Visibility = [Text.StringBuilder]::New('hide:')
				If ($RemovedAppxPackages.'Microsoft.WindowsMaps')
				{
					RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\Maps" -Name "AutoUpdateEnabled" -Value 0 -Type DWord
					If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\MapsBroker") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\MapsBroker" -Name "Start" -Value 4 -Type DWord }
					[Void]$Visibility.Append('maps;maps-downloadmaps;')
				}
				If ($RemovedAppxPackages.'Microsoft.Wallet' -and (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\WalletService")) { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\WalletService" -Name "Start" -Value 4 -Type DWord }
				If ($RemovedAppxPackages.'Microsoft.Windows.Photos')
				{
					@('.bmp', '.cr2', '.dib', '.gif', '.ico', '.jfif', '.jpe', '.jpeg', '.jpg', '.jxr', '.png', '.tif', '.tiff', '.wdp') | ForEach-Object -Process {
						RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Classes\$($PSItem)" -Name "(default)" -Value "PhotoViewer.FileAssoc.Tiff" -Type String
						RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$($PSItem)\OpenWithProgids" -Name "PhotoViewer.FileAssoc.Tiff" -Value 0 -Type Binary
					}
					@('Paint.Picture', 'giffile', 'jpegfile', 'pngfile') | ForEach-Object -Process {
						RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\$($PSItem)\shell\open" -Name "MuiVerb" -Value "@%ProgramFiles%\Windows Photo Viewer\photoviewer.dll,-3043" -Type ExpandString
						RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\$($PSItem)\shell\open\command" -Name "(Default)" -Value "%SystemRoot%\System32\rundll32.exe `"%ProgramFiles%\Windows Photo Viewer\PhotoViewer.dll`", ImageView_Fullscreen %1" -Type ExpandString
					}
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\Applications\photoviewer.dll\shell\open" -Name "MuiVerb" -Value "@photoviewer.dll,-3043" -Type String
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\Applications\photoviewer.dll\shell\open\command" -Name "(Default)" -Value "%SystemRoot%\System32\rundll32.exe `"%ProgramFiles%\Windows Photo Viewer\PhotoViewer.dll`", ImageView_Fullscreen %1" -Type ExpandString
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\Applications\photoviewer.dll\shell\open\DropTarget" -Name "Clsid" -Value "{FFE2A43C-56B9-4bf5-9A79-CC6D4285608A}" -Type String
				}
				If ($RemovedAppxPackages.Keys -like "*Xbox*" -or $RemovedSystemApps.'Microsoft.XboxGameCallableUI')
				{
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AudioCaptureEnabled" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "CursorCaptureEnabled" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\GameBar" -Name "UseNexusForGameBarEnabled" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\System\GameConfigStore" -Name "GameDVR_FSEBehavior" -Value 2 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord
					@("xbgm", "XblAuthManager", "XblGameSave", "xboxgip", "XboxGipSvc", "XboxNetApiSvc") | ForEach-Object -Process { If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\$($PSItem)") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\$($PSItem)" -Name "Start" -Value 4 -Type DWord } }
					[Void]$Visibility.Append('gaming-gamebar;gaming-gamedvr;gaming-broadcasting;gaming-gamemode;gaming-xboxnetworking;quietmomentsgame;')
					If ($InstallInfo.Build -lt '17763') { [Void]$Visibility.Append('gaming-trueplay;') }
				}
				If ($RemovedAppxPackages.'Microsoft.YourPhone' -or $RemovedSystemApps.'Microsoft.Windows.CallingShellApp')
				{
					[Void]$Visibility.Append('mobile-devices;mobile-devices-addphone;mobile-devices-addphone-direct;')
					If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\PhoneSvc") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\PhoneSvc" -Name "Start" -Value 4 -Type DWord }
				}
				If ($RemovedSystemApps.'Microsoft.MicrosoftEdge' -and !$MicrosoftEdge.IsPresent) { RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\EdgeUpdate" -Name "DoNotUpdateToEdgeWithChromium" -Value 1 -Type DWord }
				If ($RemovedSystemApps.'Microsoft.BioEnrollment')
				{
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Biometrics" -Name "Enabled" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Biometrics\Credential Provider" -Name "Enabled" -Value 0 -Type DWord
					If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\WbioSrvc") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\WbioSrvc" -Name "Start" -Value 4 -Type DWord }
				}
				If ($RemovedSystemApps.'Microsoft.Windows.SecureAssessmentBrowser')
				{
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SecureAssessment" -Name "AllowScreenMonitoring" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SecureAssessment" -Name "AllowTextSuggestions" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\SecureAssessment" -Name "RequirePrinting" -Value 0 -Type DWord
				}
				If ($RemovedSystemApps.'Microsoft.Windows.ContentDeliveryManager')
				{
					@("SubscribedContent-202914Enabled", "SubscribedContent-280810Enabled", "SubscribedContent-280811Enabled", "SubscribedContent-280813Enabled", "SubscribedContent-280815Enabled",
						"SubscribedContent-310091Enabled", "SubscribedContent-310092Enabled", "SubscribedContent-310093Enabled", "SubscribedContent-314381Enabled", "SubscribedContent-314559Enabled",
						"SubscribedContent-314563Enabled", "SubscribedContent-338380Enabled", "SubscribedContent-338387Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled",
						"SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled", "SubscribedContent-353698Enabled", "SubscribedContent-8800010Enabled",
						"ContentDeliveryAllowed", "FeatureManagementEnabled", "OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "RemediationRequired",
						"RotatingLockScreenEnabled", "RotatingLockScreenOverlayEnabled", "SilentInstalledAppsEnabled", "SoftLandingEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContentEnabled") | ForEach-Object -Process { RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name $PSItem -Value 0 -Type DWord }
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Policies\Microsoft\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "NoCloudApplicationNotification" -Value 1 -Type DWord
				}
				If ($RemovedSystemApps.'Microsoft.Windows.SecHealthUI')
				{
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SpyNetReporting" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SubmitSamplesConsent" -Value 2 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine" -Name "MpEnablePus" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Reporting" -Name "DisableEnhancedNotifications" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableBehaviorMonitoring" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableOnAccessProtection" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableScanOnRealtimeEnable" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableIOAVProtection" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "AllowBehaviorMonitoring" -Value 2 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "AllowCloudProtection" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "AllowRealtimeMonitoring" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager" -Name "SubmitSamplesConsent" -Value 2 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration" -Name "Notification_Suppress" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MRT" -Name "DontOfferThroughWUAU" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MRT" -Name "DontReportInfectionInformation" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" -Name "HideSystray" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows Security Health\State" -Name "AccountProtection_MicrosoftAccount_Disconnected" -Value 1 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows Security Health\State" -Name "AppAndBrowser_EdgeSmartScreenOff" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" -Name "SmartScreenEnabled" -Value "Off" -Type String
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Off" -Type String
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Off" -Type String
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" -Name "EnableWebContentEvaluation" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost" -Name "EnableWebContentEvaluation" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableSmartScreen" -Value 0 -Type DWord
					@("SecurityHealthService", "WinDefend", "WdNisSvc", "WdNisDrv", "WdBoot", "WdFilter", "Sense") | ForEach-Object -Process { If (Test-Path -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\$($PSItem)") { RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\$($PSItem)" -Name "Start" -Value 4 -Type DWord } }
					@("HKLM:\WIM_HKLM_SOFTWARE\Classes\*\shellex\ContextMenuHandlers\EPP", "HKLM:\WIM_HKLM_SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers\EPP", "HKLM:\WIM_HKLM_SOFTWARE\Classes\Drive\shellex\ContextMenuHandlers\EPP",
						"HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Control\WMI\AutoLogger\DefenderApiLogger", "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Control\WMI\AutoLogger\DefenderAuditLogger") | Purge
					Remove-ItemProperty -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "SecurityHealth" -Force -ErrorAction SilentlyContinue
					If (!$DynamicParams.LTSC)
					{
						RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
						RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
					}
					If ($InstallInfo.Build -ge '17763')
					{
						RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen" -Name "ConfigureAppInstallControlEnabled" -Value 1 -Type DWord
						RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen" -Name "ConfigureAppInstallControl" -Value "Anywhere" -Type String
					}
					[Void]$Visibility.Append('windowsdefender;')
					$DynamicParams.SecHealthUI = $true
				}
				If ($Visibility.Length -gt 5)
				{
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "SettingsPageVisibility" -Value $Visibility.ToString().TrimEnd(';') -Type String
					RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "SettingsPageVisibility" -Value $Visibility.ToString().TrimEnd(';') -Type String
				}
			}
			Catch
			{
				Log -Error $OptimizedData.FailedPackageCleanup
				$OptimizeErrors.Add($Error[0])
				Start-Sleep 3
			}
			Finally
			{
				RegHives -Unload
			}

			If ($DynamicParams.SecHealthUI -and (Get-WindowsOptionalFeature -Path $InstallMount -FeatureName Windows-Defender-Default-Definitions | Where-Object -Property State -EQ Enabled))
			{
				Try
				{
					$DisableDefenderOptionalFeature = @{
						Path             = $InstallMount
						FeatureName      = 'Windows-Defender-Default-Definitions'
						Remove           = $true
						NoRestart        = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						ErrorAction      = 'Stop'
					}
					Log -Info $OptimizedData.DisablingDefenderOptionalFeature
					[Void](Disable-WindowsOptionalFeature @DisableDefenderOptionalFeature)
				}
				Catch
				{
					Log -Error $OptimizedData.FailedDisablingDefenderOptionalFeature
					$OptimizeErrors.Add($Error[0])
					Start-Sleep 3
				}
			}
		}
		#endregion Removed Package Clean-up

		#region Import Custom App Associations
		If (Test-Path -Path $OptimizeOffline.CustomAppAssociations)
		{
			Try
			{
				Log -Info $OptimizedData.ImportingCustomAppAssociations
				$RET = StartExe $DISM -Arguments ('/Image:"{0}" /Import-DefaultAppAssociations:"{1}" /ScratchDir:"{2}" /LogPath:"{3}"' -f $InstallMount, $OptimizeOffline.CustomAppAssociations, $ScratchFolder, $DISMLog) -ErrorAction Stop
				If ($RET -ne 0) { Throw }
			}
			Catch
			{
				Log -Error $OptimizedData.FailedImportingCustomAppAssociations
				$OptimizeErrors.Add($Error[0])
				Start-Sleep 3
			}
		}
		#endregion Import Custom App Associations

		#region Windows Capability and Cabinet File Package Removal
		If ($Capabilities.IsPresent)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Remove Windows Capabilities."
			$WindowsCapabilities = Get-WindowsCapability -Path $InstallMount | Where-Object { $PSItem.Name -notlike "*Language.Basic*" -and $PSItem.Name -notlike "*TextToSpeech*" -and $PSItem.State -eq 'Installed' } | Select-Object -Property Name, State | Sort-Object -Property Name | Out-GridView -Title "Remove Windows Capabilities." -PassThru
			If ($WindowsCapabilities)
			{
				Try
				{
					$WindowsCapabilities | ForEach-Object -Process {
						$RemoveCapabilityParams = @{
							Path             = $InstallMount
							Name             = $PSItem.Name
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							ErrorAction      = 'Stop'
						}
						Log -Info ($OptimizedData.RemovingWindowsCapability -f $PSItem.Name.Split('~')[0])
						[Void](Remove-WindowsCapability @RemoveCapabilityParams)
					}
					$DynamicParams.Capabilities = $true
				}
				Catch
				{
					Log -Error $OptimizedData.FailedRemovingWindowsCapabilities
					$OptimizeErrors.Add($Error[0])
					Stop-Optimize
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
		}

		If ($Packages.IsPresent)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Remove Windows Packages."
			$WindowsPackages = Get-WindowsPackage -Path $InstallMount | Where-Object { $PSItem.PackageName -notlike "*LanguageFeatures-Basic*" -and $PSItem.PackageName -notlike "*LanguageFeatures-TextToSpeech*" -and $PSItem.ReleaseType -eq 'OnDemandPack' -or $PSItem.ReleaseType -eq 'LanguagePack' -or $PSItem.ReleaseType -eq 'FeaturePack' -and $PSItem.PackageState -eq 'Installed' } | Select-Object -Property PackageName, ReleaseType | Sort-Object -Property ReleaseType -Descending | Out-GridView -Title "Remove Windows Packages." -PassThru
			If ($WindowsPackages)
			{
				Try
				{
					$WindowsPackages | ForEach-Object -Process {
						$RemovePackageParams = @{
							Path             = $InstallMount
							PackageName      = $PSItem.PackageName
							NoRestart        = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							ErrorAction      = 'Stop'
						}
						Log -Info ($OptimizedData.RemovingWindowsPackage -f $PSItem.PackageName.Replace('Package', $null).Split('~')[0].TrimEnd('-'))
						[Void](Remove-WindowsPackage @RemovePackageParams)
					}
					$DynamicParams.Packages = $true
				}
				Catch
				{
					Log -Error $OptimizedData.FailedRemovingWindowsPackages
					$OptimizeErrors.Add($Error[0])
					Stop-Optimize
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
		}
		#endregion Windows Capability and Cabinet File Package Removal

		#region Disable Unsafe Optional Features
		#@('SMB1Protocol', 'MicrosoftWindowsPowerShellV2Root') | ForEach-Object -Process { Get-WindowsOptionalFeature -Path $InstallMount -FeatureName $PSItem | Where-Object -Property State -EQ Disabled | Disable-WindowsOptionalFeature -Path $InstallMount -Remove -NoRestart -ScratchDirectory $ScratchFolder -LogPath $DISMLog -ErrorAction SilentlyContinue }
		ForEach ($Feature In @('SMB1Protocol', 'MicrosoftWindowsPowerShellV2Root'))
		{
			If (Get-WindowsOptionalFeature -Path $InstallMount -FeatureName $Feature | Where-Object -Property State -EQ Enabled)
			{
				Try
				{
					Log -Info ($OptimizedData.DisablingUnsafeOptionalFeature -f $Feature)
					$DisableOptionalFeatureParams = @{
						Path             = $InstallMount
						FeatureName      = $Feature
						Remove           = $true
						NoRestart        = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						ErrorAction      = 'Stop'
					}
					[Void](Disable-WindowsOptionalFeature @DisableOptionalFeatureParams)
				}
				Catch
				{
					Log -Error ($OptimizedData.FailedDisablingUnsafeOptionalFeature -f $Feature)
					$OptimizeErrors.Add($Error[0])
					Stop-Optimize
				}
			}
		}
		#endregion Disable Unsafe Optional Features

		#region Disable/Enable Optional Features
		If ($Features.IsPresent)
		{
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Disable Optional Features."
			$DisableFeatures = Get-WindowsOptionalFeature -Path $InstallMount | Where-Object -Property State -EQ Enabled | Select-Object -Property FeatureName, State | Sort-Object -Property FeatureName | Out-GridView -Title "Disable Optional Features." -PassThru
			If ($DisableFeatures)
			{
				Try
				{
					$DisableFeatures | ForEach-Object -Process {
						$DisableFeatureParams = @{
							Path             = $InstallMount
							FeatureName      = $PSItem.FeatureName
							Remove           = $true
							NoRestart        = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							ErrorAction      = 'Stop'
						}
						Log -Info ($OptimizedData.DisablingOptionalFeature -f $PSItem.FeatureName)
						[Void](Disable-WindowsOptionalFeature @DisableFeatureParams)
					}
					$DynamicParams.DisabledOptionalFeatures = $true
				}
				Catch
				{
					Log -Error $OptimizedData.FailedDisablingOptionalFeatures
					$OptimizeErrors.Add($Error[0])
					Stop-Optimize
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
			Clear-Host
			$Host.UI.RawUI.WindowTitle = "Enable Optional Features."
			$EnableFeatures = Get-WindowsOptionalFeature -Path $InstallMount | Where-Object { $PSItem.FeatureName -notlike "SMB1Protocol*" -and $PSItem.FeatureName -ne "Windows-Defender-Default-Definitions" -and $PSItem.FeatureName -notlike "MicrosoftWindowsPowerShellV2*" -and $PSItem.State -eq "Disabled" } | Select-Object -Property FeatureName, State | Sort-Object -Property FeatureName | Out-GridView -Title "Enable Optional Features." -PassThru
			If ($EnableFeatures)
			{
				Try
				{
					$EnableFeatures | ForEach-Object -Process {
						$EnableFeatureParams = @{
							Path             = $InstallMount
							FeatureName      = $PSItem.FeatureName
							All              = $true
							LimitAccess      = $true
							NoRestart        = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							ErrorAction      = 'Stop'
						}
						Log -Info ($OptimizedData.EnablingOptionalFeature -f $PSItem.FeatureName)
						[Void](Enable-WindowsOptionalFeature @EnableFeatureParams)
					}
					$DynamicParams.EnabledOptionalFeatures = $true
				}
				Catch
				{
					Log -Error $OptimizedData.FailedEnablingOptionalFeatures
					$OptimizeErrors.Add($Error[0])
					Stop-Optimize
				}
				$Host.UI.RawUI.WindowTitle = $null; Clear-Host
			}
		}
		#endregion Disable/Enable Optional Features

		#region DeveloperMode Integration
		If ($DeveloperMode.IsPresent -and (Test-Path -Path $OptimizeOffline.DevMode -Filter *DeveloperMode-Desktop-Package*.cab) -and !(Get-WindowsPackage -Path $InstallMount | Where-Object -Property PackageName -Like *DeveloperMode*))
		{
			$DevModeExpand = Create -Path (GetPath -Path $WorkFolder -Child DeveloperMode) -PassThru
			[Void](StartExe $EXPAND -Arguments ('"{0}" F:* "{1}"' -f (GetPath -Path $OptimizeOffline.DevMode -Child "Microsoft-OneCore-DeveloperMode-Desktop-Package~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).1.cab"), $DevModeExpand.FullName))
			Try
			{
				Log -Info $OptimizedData.IntegratingDeveloperMode
				$RET = StartExe $DISM -Arguments ('/Image:"{0}" /Add-Package /PackagePath:"{1}" /ScratchDir:"{2}" /LogPath:"{3}"' -f $InstallMount, (GetPath -Path $DevModeExpand.FullName -Child update.mum), $ScratchFolder, $DISMLog) -ErrorAction Stop
				If ($RET -eq 0) { $DynamicParams.DeveloperMode = $true }
				Else { Throw }
			}
			Catch
			{
				Log -Error $OptimizedData.FailedIntegratingDeveloperMode
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
			If ($DynamicParams.DeveloperMode)
			{
				RegHives -Load
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowAllTrustedApps" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord
				RegHives -Unload
			}
		}
		#endregion DeveloperMode Integration

		#region Windows Store Integration
		If ($WindowsStore.IsPresent -and (Test-Path -Path $OptimizeOffline.WindowsStore -Filter Microsoft.WindowsStore*.appxbundle) -and !(Get-AppxProvisionedPackage -Path $InstallMount | Where-Object -Property DisplayName -EQ Microsoft.WindowsStore))
		{
			Log -Info $OptimizedData.IntegratingWindowsStore
			$StoreBundle = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.WindowsStore*.appxbundle -File | Select-Object -ExpandProperty FullName
			$PurchaseBundle = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.StorePurchaseApp*.appxbundle -File | Select-Object -ExpandProperty FullName
			$XboxBundle = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.XboxIdentityProvider*.appxbundle -File | Select-Object -ExpandProperty FullName
			$InstallerBundle = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.DesktopAppInstaller*.appxbundle -File | Select-Object -ExpandProperty FullName
			$StoreLicense = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.WindowsStore*.xml -File | Select-Object -ExpandProperty FullName
			$PurchaseLicense = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.StorePurchaseApp*.xml -File | Select-Object -ExpandProperty FullName
			$XboxLicense = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.XboxIdentityProvider*.xml -File | Select-Object -ExpandProperty FullName
			$InstallerLicense = Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.DesktopAppInstaller*.xml -File | Select-Object -ExpandProperty FullName
			$DependencyPackages = @()
			$DependencyPackages += Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter Microsoft.VCLibs*.appx -File | Select-Object -ExpandProperty FullName
			$DependencyPackages += Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter *Native.Framework*.appx -File | Select-Object -ExpandProperty FullName
			$DependencyPackages += Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter *Native.Runtime*.appx -File | Select-Object -ExpandProperty FullName
			RegHives -Load
			RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowAllTrustedApps" -Value 1 -Type DWord
			RegHives -Unload
			Try
			{
				$StorePackage = @{
					Path                  = $InstallMount
					PackagePath           = $StoreBundle
					DependencyPackagePath = $DependencyPackages
					LicensePath           = $StoreLicense
					ScratchDirectory      = $ScratchFolder
					LogPath               = $DISMLog
					ErrorAction           = 'Stop'
				}
				[Void](Add-AppxProvisionedPackage @StorePackage)
				$PurchasePackage = @{
					Path                  = $InstallMount
					PackagePath           = $PurchaseBundle
					DependencyPackagePath = $DependencyPackages
					LicensePath           = $PurchaseLicense
					ScratchDirectory      = $ScratchFolder
					LogPath               = $DISMLog
					ErrorAction           = 'Stop'
				}
				[Void](Add-AppxProvisionedPackage @PurchasePackage)
				$XboxPackage = @{
					Path                  = $InstallMount
					PackagePath           = $XboxBundle
					DependencyPackagePath = $DependencyPackages
					LicensePath           = $XboxLicense
					ScratchDirectory      = $ScratchFolder
					LogPath               = $DISMLog
					ErrorAction           = 'Stop'
				}
				[Void](Add-AppxProvisionedPackage @XboxPackage)
				$DependencyPackages = @()
				$DependencyPackages += Get-ChildItem -Path $OptimizeOffline.WindowsStore -Filter *Native.Runtime*.appx -File | Select-Object -ExpandProperty FullName
				$InstallerPackage = @{
					Path                  = $InstallMount
					PackagePath           = $InstallerBundle
					DependencyPackagePath = $DependencyPackages
					LicensePath           = $InstallerLicense
					ScratchDirectory      = $ScratchFolder
					LogPath               = $DISMLog
					ErrorAction           = 'Stop'
				}
				[Void](Add-AppxProvisionedPackage @InstallerPackage)
				$DynamicParams.WindowsStore = $true
			}
			Catch
			{
				Log -Error $OptimizedData.FailedIntegratingWindowsStore
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
			Finally
			{
				If (!$DynamicParams.DeveloperMode)
				{
					RegHives -Load
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowAllTrustedApps" -Value 0 -Type DWord
					RegHives -Unload
				}
			}
		}
		#endregion Windows Store Integration

		#region Microsoft Edge Integration
		If ($MicrosoftEdge.IsPresent -and (Test-Path -Path $OptimizeOffline.MicrosoftEdge -Filter Microsoft-Windows-Internet-Browser-Package*.cab) -and !(Get-WindowsPackage -Path $InstallMount | Where-Object -Property PackageName -Like *Internet-Browser*))
		{
			Try
			{
				Log -Info $OptimizedData.IntegratingMicrosoftEdge
				@((GetPath -Path $OptimizeOffline.MicrosoftEdge -Child "Microsoft-Windows-Internet-Browser-Package~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).1.cab"),
					(GetPath -Path $OptimizeOffline.MicrosoftEdge -Child "Microsoft-Windows-Internet-Browser-Package~$($InstallInfo.Architecture)~$($InstallInfo.Language)~10.0.$($InstallInfo.Build).1.cab")) | ForEach-Object -Process { [Void](Add-WindowsPackage -Path $InstallMount -PackagePath $PSItem -IgnoreCheck -ScratchDirectory $ScratchFolder -LogPath $DISMLog -ErrorAction Stop) }
				$DynamicParams.MicrosoftEdge = $true
			}
			Catch
			{
				Log -Error $OptimizedData.FailedIntegratingMicrosoftEdge
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
			If ($DynamicParams.MicrosoftEdge)
			{
				RegHives -Load
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "DisableEdgeDesktopShortcutCreation" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" -Name "AllowPrelaunch" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" -Name "AllowPrelaunch" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\Main" -Name "AllowPrelaunch" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKCU\SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader" -Name "PreventTabPreloading" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader" -Name "PreventTabPreloading" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\TabPreloader" -Name "PreventTabPreloading" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" -Name "DoNotTrack" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\Main" -Name "DoNotTrack" -Value 1 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\Addons" -Name "FlashPlayerEnabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\Addons" -Name "FlashPlayerEnabled" -Value 0 -Type DWord
				If ($DynamicParams.SecHealthUI)
				{
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
					RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Policies\Microsoft\MicrosoftEdge\PhishingFilter" -Name "EnabledV9" -Value 0 -Type DWord
				}
				RegHives -Unload
			}
		}
		#endregion Microsoft Edge Integration

		#region Win32 Calculator Integration
		If ($Win32Calc.IsPresent -and (Test-Path -Path $OptimizeOffline.Win32Calc -Filter Win32Calc.wim) -and !(Get-WindowsPackage -Path $InstallMount | Where-Object -Property PackageName -Like *win32calc*))
		{
			Try
			{
				Log -Info $OptimizedData.IntegratingWin32Calc
				$ExpandCalcParams = @{
					ImagePath        = '{0}\Win32Calc.wim' -f $OptimizeOffline.Win32Calc
					Index            = 1
					ApplyPath        = $InstallMount
					CheckIntegrity   = $true
					Verify           = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					ErrorAction      = 'Stop'
				}
				[Void](Expand-WindowsImage @ExpandCalcParams)
				Add-Content -Path (GetPath -Path $InstallMount -Child 'ProgramData\Microsoft\Windows\Start Menu\Programs\Accessories\desktop.ini') -Value 'Calculator.lnk=@%SystemRoot%\System32\shell32.dll,-22019' -Encoding Unicode -Force -ErrorAction Stop
				$DynamicParams.Win32Calc = $true
			}
			Catch
			{
				Log -Error $OptimizedData.FailedIntegratingWin32Calc
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
			If ($DynamicParams.Win32Calc)
			{
				RegHives -Load
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\RegisteredApplications" -Name "Windows Calculator" -Value "SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\RegisteredApplications" -Name "Windows Calculator" -Value "SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\calculator" -Name "(default)" -Value "URL:calculator" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\calculator" -Name "URL Protocol" -Value "" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\calculator\DefaultIcon" -Name "(default)" -Value "C:\Windows\System32\win32calc.exe,0" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Classes\calculator\shell\open\command" -Name "(default)" -Value "C:\Windows\System32\win32calc.exe" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\ShellCompatibility\InboxApp" -Name "56230F2FD0CC3EB4_Calculator_lnk_amd64.lnk" -Value "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Accessories\Calculator.lnk" -Type ExpandString -Force
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\App Management\WindowsFeatureCategories" -Name "COMMONSTART/Programs/Accessories/Calculator.lnk" -Value "SOFTWARE_CATEGORY_UTILITIES" -Type String -Force
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Management\WindowsFeatureCategories" -Name "COMMONSTART/Programs/Accessories/Calculator.lnk" -Value "SOFTWARE_CATEGORY_UTILITIES" -Type String -Force
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Name "ApplicationName" -Value "%SystemRoot%\System32\win32calc.exe" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Name "ApplicationName" -Value "%SystemRoot%\System32\win32calc.exe" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Name "ApplicationDescription" -Value "%SystemRoot%\System32\win32calc.exe,-217" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities" -Name "ApplicationDescription" -Value "%SystemRoot%\System32\win32calc.exe,-217" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities\URLAssociations" -Name "calculator" -Value "calculator" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Applets\Calculator\Capabilities\URLAssociations" -Name "calculator" -Value "calculator" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Debug" -Name "OwningPublisher" -Value "{75f48521-4131-4ac3-9887-65473224fcb2}" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Debug" -Name "Enabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Debug" -Name "Isolation" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Debug" -Name "ChannelAccess" -Value "O:BAG:SYD:(A;;0x2;;;S-1-15-2-1)(A;;0xf0007;;;SY)(A;;0x7;;;BA)(A;;0x7;;;SO)(A;;0x3;;;IU)(A;;0x3;;;SU)(A;;0x3;;;S-1-5-3)(A;;0x3;;;S-1-5-33)(A;;0x1;;;S-1-5-32-573)" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Debug" -Name "Type" -Value 3 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Diagnostic" -Name "OwningPublisher" -Value "{75f48521-4131-4ac3-9887-65473224fcb2}" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Diagnostic" -Name "Enabled" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Diagnostic" -Name "Isolation" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Diagnostic" -Name "ChannelAccess" -Value "O:BAG:SYD:(A;;0x2;;;S-1-15-2-1)(A;;0xf0007;;;SY)(A;;0x7;;;BA)(A;;0x7;;;SO)(A;;0x3;;;IU)(A;;0x3;;;SU)(A;;0x3;;;S-1-5-3)(A;;0x3;;;S-1-5-33)(A;;0x1;;;S-1-5-32-573)" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Calculator/Diagnostic" -Name "Type" -Value 2 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}" -Name "(default)" -Value "Microsoft-Windows-Calculator" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}" -Name "ResourceFileName" -Value "%SystemRoot%\System32\win32calc.exe" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}" -Name "MessageFileName" -Value "%SystemRoot%\System32\win32calc.exe" -Type ExpandString
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences" -Name "Count" -Value 2 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\0" -Name "(default)" -Value "Microsoft-Windows-Calculator/Diagnostic" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\0" -Name "Id" -Value 16 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\0" -Name "Flags" -Value 0 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\1" -Name "(default)" -Value "Microsoft-Windows-Calculator/Debug" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\1" -Name "Id" -Value 17 -Type DWord
				RegKey -Path "HKLM:\WIM_HKLM_SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Publishers\{75f48521-4131-4ac3-9887-65473224fcb2}\ChannelReferences\1" -Name "Flags" -Value 0 -Type DWord
				RegHives -Unload
			}
		}
		#endregion Win32 Calculator Integration

		#region Data Deduplication Integration
		If ($Dedup.IsPresent -and (Test-Path -Path $OptimizeOffline.Dedup -Filter Microsoft-Windows-FileServer-ServerCore-Package*.cab) -and (Test-Path -Path $OptimizeOffline.Dedup -Filter Microsoft-Windows-Dedup-Package*.cab) -and !(Get-WindowsPackage -Path $InstallMount | Where-Object { $PSItem.PackageName -like "*Windows-Dedup*" -or $PSItem.PackageName -like "*FileServer-ServerCore*" }))
		{
			Try
			{
				Log -Info $OptimizedData.IntegratingDataDedup
				@((GetPath -Path $OptimizeOffline.Dedup -Child "Microsoft-Windows-FileServer-ServerCore-Package~31bf3856ad364e35~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).1.cab"),
					(GetPath -Path $OptimizeOffline.Dedup -Child "Microsoft-Windows-FileServer-ServerCore-Package~31bf3856ad364e35~$($InstallInfo.Architecture)~$($InstallInfo.Language)~10.0.$($InstallInfo.Build).1.cab"),
					(GetPath -Path $OptimizeOffline.Dedup -Child "Microsoft-Windows-Dedup-Package~31bf3856ad364e35~$($InstallInfo.Architecture)~~10.0.$($InstallInfo.Build).1.cab"),
					(GetPath -Path $OptimizeOffline.Dedup -Child "Microsoft-Windows-Dedup-Package~31bf3856ad364e35~$($InstallInfo.Architecture)~$($InstallInfo.Language)~10.0.$($InstallInfo.Build).1.cab")) | ForEach-Object -Process { [Void](Add-WindowsPackage -Path $InstallMount -PackagePath $PSItem -IgnoreCheck -ScratchDirectory $ScratchFolder -LogPath $DISMLog -ErrorAction Stop) }
				$EnableDedup = @{
					Path             = $InstallMount
					FeatureName      = 'Dedup-Core'
					All              = $true
					LimitAccess      = $true
					NoRestart        = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					ErrorAction      = 'Stop'
				}
				[Void](Enable-WindowsOptionalFeature @EnableDedup)
				$DynamicParams.DataDeduplication = $true
			}
			Catch
			{
				Log -Error $OptimizedData.FailedIntegratingDataDedup
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
			If ($DynamicParams.DataDeduplication)
			{
				RegHives -Load
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\SharedAccess\Defaults\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-DCOM-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=135|App=%systemroot%\\system32\\svchost.exe|Svc=RPCSS|Name=@fssmres.dll,-103|Desc=@fssmres.dll,-104|EmbedCtxt=@fssmres.dll,-100|" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\SharedAccess\Defaults\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-SMB-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=445|App=System|Name=@fssmres.dll,-105|Desc=@fssmres.dll,-106|EmbedCtxt=@fssmres.dll,-100|" -Type String
				RegKey -Path "HKLM:\WIM_HKLM_SYSTEM\ControlSet001\Services\SharedAccess\Defaults\FirewallPolicy\FirewallRules" -Name "FileServer-ServerManager-Winmgmt-TCP-In" -Value "v2.29|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=RPC|App=%systemroot%\\system32\\svchost.exe|Svc=Winmgmt|Name=@fssmres.dll,-101|Desc=@fssmres.dll,-102|EmbedCtxt=@fssmres.dll,-100|" -Type String
				RegHives -Unload
			}
		}
		#endregion Data Deduplication Integration

		#region Microsoft DaRT 10 Integration
		If ($DaRT -and (Test-Path -Path $OptimizeOffline.DaRT -Filter MSDaRT10_*.wim))
		{
			If ($InstallInfo.Build -eq '17134') { $CodeName = 'RS4' }
			ElseIf ($InstallInfo.Build -eq '17763') { $CodeName = 'RS5' }
			ElseIf ($InstallInfo.Build -ge '18362') { $CodeName = '19H2' }
			Try
			{
				If ($PSBoundParameters.DaRT -eq 'Setup' -or $PSBoundParameters.DaRT -eq 'All' -and $DynamicParams.Boot)
				{
					Log -Info ($OptimizedData.IntegratingDaRT10 -f $CodeName, $BootInfo.Name)
					$ExpandDaRTBootParams = @{
						ImagePath        = '{0}\MSDaRT10_{1}.wim' -f $OptimizeOffline.DaRT, $CodeName
						Index            = 1
						ApplyPath        = $BootMount
						CheckIntegrity   = $true
						Verify           = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						ErrorAction      = 'Stop'
					}
					[Void](Expand-WindowsImage @ExpandDaRTBootParams)
					If (!(Test-Path -Path (GetPath -Path $BootMount -Child 'Windows\System32\fmapi.dll'))) { Copy-Item -Path (GetPath -Path $InstallMount -Child 'Windows\System32\fmapi.dll') -Destination (GetPath -Path $BootMount -Child 'Windows\System32\fmapi.dll') -Force -ErrorAction Stop }
					@'
[LaunchApps]
%WINDIR%\System32\wpeinit.exe
%WINDIR%\System32\netstart.exe
%SYSTEMDRIVE%\setup.exe
'@ | Out-File -FilePath (GetPath -Path $BootMount -Child 'Windows\System32\winpeshl.ini') -Force -ErrorAction Stop
				}
				If ($PSBoundParameters.DaRT -eq 'Recovery' -or $PSBoundParameters.DaRT -eq 'All' -and $DynamicParams.Recovery)
				{
					Log -Info ($OptimizedData.IntegratingDaRT10 -f $CodeName, $RecoveryInfo.Name)
					$ExpandDaRTRecoveryParams = @{
						ImagePath        = '{0}\MSDaRT10_{1}.wim' -f $OptimizeOffline.DaRT, $CodeName
						Index            = 1
						ApplyPath        = $RecoveryMount
						CheckIntegrity   = $true
						Verify           = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						ErrorAction      = 'Stop'
					}
					[Void](Expand-WindowsImage @ExpandDaRTRecoveryParams)
					If (!(Test-Path -Path (GetPath -Path $RecoveryMount -Child 'Windows\System32\fmapi.dll'))) { Copy-Item -Path (GetPath -Path $InstallMount -Child 'Windows\System32\fmapi.dll') -Destination (GetPath -Path $RecoveryMount -Child 'Windows\System32\fmapi.dll') -Force -ErrorAction Stop }
					@'
[LaunchApps]
%WINDIR%\System32\wpeinit.exe
%WINDIR%\System32\netstart.exe
%SYSTEMDRIVE%\sources\recovery\recenv.exe
'@ | Out-File -FilePath (GetPath -Path $RecoveryMount -Child 'Windows\System32\winpeshl.ini') -Force -ErrorAction Stop
				}
			}
			Catch
			{
				Log -Error $OptimizedData.FailedIntegratingDaRT10
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
			Finally
			{
				Start-Sleep 3; Clear-Host
			}
		}
		#endregion Microsoft DaRT 10 Integration

		#region Apply Optimized Registry Settings
		If ($Registry.IsPresent)
		{
			If (Test-Path -Path (GetPath -Path $OptimizeOffline.Resources -Child "Public\$($OptimizeOffline.Culture)\Set-RegistryProperties.strings.psd1"))
			{
				Try
				{
					Log -Info "Applying Optimized Registry Settings."
					Set-RegistryProperties -ErrorAction Stop
				}
				Catch
				{
					Log -Error $OptimizedData.FailedApplyingRegistrySettings
					$OptimizeErrors.Add($Error[0])
					Stop-Optimize
				}
				Finally
				{
					If (RegHives -Test) { RegHives -Unload }
				}
			}
			Else
			{
				Log -Error ($OptimizedData.MissingRequiredRegistryData -f (GetPath -Path (GetPath -Path $OptimizeOffline.Resources -Child "Public\$($OptimizeOffline.Culture)\Set-RegistryProperties.strings.psd1") -Split Leaf))
				Start-Sleep 3
			}
		}
		#endregion Apply Optimized Registry Settings

		#region Additional Content Integration
		If ($Additional.Values -contains $true)
		{
			If ($Additional.Setup -and (Test-Path -Path (GetPath -Path $OptimizeOffline.Setup -Child *)))
			{
				Try
				{
					Log -Info $OptimizedData.ApplyingSetupContent
					(GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts') | Create
					Get-ChildItem -Path $OptimizeOffline.Setup -Exclude RebootRecovery.png, RefreshExplorer.png, README.md | Copy-Item -Destination (GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts') -Recurse -Force -ErrorAction Stop
				}
				Catch
				{
					Log -Error $OptimizedData.FailedApplyingSetupContent
					$OptimizeErrors.Add($Error[0])
					(GetPath -Path $InstallMount -Child 'Windows\Setup\Scripts') | Purge -ErrorAction SilentlyContinue
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.Wallpaper -and (Test-Path -Path (GetPath -Path $OptimizeOffline.Wallpaper -Child *)))
			{
				Try
				{
					Log -Info $OptimizedData.ApplyingWallpaper
					Get-ChildItem -Path $OptimizeOffline.Wallpaper -Directory | Copy-Item -Destination (GetPath -Path $InstallMount -Child 'Windows\Web\Wallpaper') -Recurse -Force -ErrorAction Stop
					Get-ChildItem -Path (GetPath -Path $OptimizeOffline.Wallpaper -Child *) -Include *.jpg, *.png, *.bmp, *.gif -File | Copy-Item -Destination (GetPath -Path $InstallMount -Child 'Windows\Web\Wallpaper') -Force -ErrorAction Stop
				}
				Catch
				{
					Log -Error $OptimizedData.FailedApplyingWallpaper
					$OptimizeErrors.Add($Error[0])
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.SystemLogo -and (Test-Path -Path (GetPath -Path $OptimizeOffline.SystemLogo -Child *.bmp)))
			{
				Try
				{
					Log -Info $OptimizedData.ApplyingSystemLogo
					(GetPath -Path $InstallMount -Child 'Windows\System32\oobe\info\logo') | Create
					Copy-Item -Path (GetPath -Path $OptimizeOffline.SystemLogo -Child *.bmp) -Destination (GetPath -Path $InstallMount -Child 'Windows\System32\oobe\info\logo') -Recurse -Force -ErrorAction Stop
				}
				Catch
				{
					Log -Error $OptimizedData.FailedApplyingSystemLogo
					$OptimizeErrors.Add($Error[0])
					(GetPath -Path $InstallMount -Child 'Windows\System32\oobe\info\logo') | Purge -ErrorAction SilentlyContinue
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.LockScreen -and (Test-Path -Path (GetPath -Path $OptimizeOffline.LockScreen -Child *.jpg)))
			{
				Try
				{
					Log -Info $OptimizedData.ApplyingLockScreen
					Set-LockScreen -ErrorAction Stop
				}
				Catch
				{
					Log -Error $OptimizedData.FailedApplyingLockScreen
					$OptimizeErrors.Add($Error[0])
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.RegistryTemplates -and (Test-Path -Path (GetPath -Path $OptimizeOffline.RegistryTemplates -Child *.reg)))
			{
				Try
				{
					Log -Info $OptimizedData.ImportingRegistryTemplates
					Import-RegistryTemplates -ErrorAction Stop
				}
				Catch
				{
					Log -Error $OptimizedData.FailedImportingRegistryTemplates
					$OptimizeErrors.Add($Error[0])
				}
				Finally
				{
					Start-Sleep 3
				}
			}
			If ($Additional.Unattend -and (Test-Path -Path (GetPath -Path $OptimizeOffline.Unattend -Child unattend.xml)))
			{
				Try
				{
					$ApplyUnattendParams = @{
						UnattendPath     = '{0}\unattend.xml' -f $OptimizeOffline.Unattend
						Path             = $InstallMount
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						ErrorAction      = 'Stop'
					}
					Log -Info $OptimizedData.ApplyingAnswerFile
					[Void](Use-WindowsUnattend @ApplyUnattendParams)
					(GetPath -Path $InstallMount -Child 'Windows\Panther') | Create
					Copy-Item -Path (GetPath -Path $OptimizeOffline.Unattend -Child unattend.xml) -Destination (GetPath -Path $InstallMount -Child 'Windows\Panther') -Force -ErrorAction Stop
					Start-Sleep 3
				}
				Catch
				{
					Log -Error $OptimizedData.FailedApplyingAnswerFile
					$OptimizeErrors.Add($Error[0])
					(GetPath -Path $InstallMount -Child 'Windows\Panther') | Purge -ErrorAction SilentlyContinue
					Start-Sleep 3
				}
			}
			If ($Additional.Drivers)
			{
				Get-ChildItem -Path $OptimizeOffline.Drivers -Recurse -Force | ForEach-Object -Process { $PSItem.Attributes = 0x80 }
				If (Get-ChildItem -Path $OptimizeOffline.InstallDrivers -Include *.inf -Recurse -Force)
				{
					Try
					{
						$InstallDriverParams = @{
							Path             = $InstallMount
							Driver           = $OptimizeOffline.InstallDrivers
							Recurse          = $true
							ForceUnsigned    = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							ErrorAction      = 'Stop'
						}
						Log -Info ($OptimizedData.InjectingDriverPackages -f $InstallInfo.Name)
						[Void](Add-WindowsDriver @InstallDriverParams)
						$DynamicParams.InstallDrivers = $true
					}
					Catch
					{
						Log -Error ($OptimizedData.FailedInjectingDriverPackages -f $InstallInfo.Name)
						$OptimizeErrors.Add($Error[0])
						Start-Sleep 3
					}
				}
				If ($DynamicParams.Boot -and (Get-ChildItem -Path $OptimizeOffline.BootDrivers -Include *.inf -Recurse -Force))
				{
					Try
					{
						$BootDriverParams = @{
							Path             = $BootMount
							Driver           = $OptimizeOffline.BootDrivers
							Recurse          = $true
							ForceUnsigned    = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							ErrorAction      = 'Stop'
						}
						Log -Info ($OptimizedData.InjectingDriverPackages -f $BootInfo.Name)
						[Void](Add-WindowsDriver @BootDriverParams)
						$DynamicParams.BootDrivers = $true
					}
					Catch
					{
						Log -Error ($OptimizedData.FailedInjectingDriverPackages -f $BootInfo.Name)
						$OptimizeErrors.Add($Error[0])
						Start-Sleep 3
					}
				}
				If ($DynamicParams.Recovery -and (Get-ChildItem -Path $OptimizeOffline.RecoveryDrivers -Include *.inf -Recurse -Force))
				{
					Try
					{
						$RecoveryDriverParams = @{
							Path             = $RecoveryMount
							Driver           = $OptimizeOffline.RecoveryDrivers
							Recurse          = $true
							ForceUnsigned    = $true
							ScratchDirectory = $ScratchFolder
							LogPath          = $DISMLog
							ErrorAction      = 'Stop'
						}
						Log -Info ($OptimizedData.InjectingDriverPackages -f $RecoveryInfo.Name)
						[Void](Add-WindowsDriver @RecoveryDriverParams)
						$DynamicParams.RecoveryDrivers = $true
					}
					Catch
					{
						Log -Error ($OptimizedData.FailedInjectingDriverPackages -f $RecoveryInfo.Name)
						$OptimizeErrors.Add($Error[0])
						Start-Sleep 3
					}
				}
			}
			If ($Additional.NetFx3 -and (Get-ChildItem -Path (GetPath -Path $ISOMedia.FullName -Child 'sources\sxs') -Filter *netfx3*.cab) -and (Get-WindowsOptionalFeature -Path $InstallMount -FeatureName NetFx3 | Where-Object -Property State -EQ DisabledWithPayloadRemoved))
			{
				Try
				{
					$EnableNetFx3Params = @{
						Path             = $InstallMount
						FeatureName      = 'NetFx3'
						Source           = '{0}\sources\sxs' -f $ISOMedia.FullName
						All              = $true
						LimitAccess      = $true
						NoRestart        = $true
						ScratchDirectory = $ScratchFolder
						LogPath          = $DISMLog
						ErrorAction      = 'Stop'
					}
					Log -Info $OptimizedData.EnablingNetFx3
					[Void](Enable-WindowsOptionalFeature @EnableNetFx3Params)
					$DynamicParams.NetFx3 = $true
				}
				Catch
				{
					Log -Error $OptimizedData.FailedEnablingNetFx3
					$OptimizeErrors.Add($Error[0])
					Start-Sleep 3
				}
			}
		}
		#endregion Additional Content Integration

		#region Image Finalization
		Try
		{
			Log -Info $OptimizedData.CleanupStartMenu
			$LayoutModTemplate = @"
<LayoutModificationTemplate xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" Version="1"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification">
    <LayoutOptions StartTileGroupsColumnCount="2" StartTileGroupCellWidth="6" FullScreenStart="false" />
    <DefaultLayoutOverride>
        <StartLayoutCollection>
            <defaultlayout:StartLayout GroupCellWidth="6">
                <start:Group Name="$($InstallInfo.Name)">
                    <start:DesktopApplicationTile Size="2x2" Column="0" Row="0" DesktopApplicationID="Microsoft.Windows.Computer" />
                    <start:DesktopApplicationTile Size="2x2" Column="2" Row="0" DesktopApplicationID="Microsoft.Windows.ControlPanel" />
                    <start:DesktopApplicationTile Size="1x1" Column="4" Row="0" DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\Windows PowerShell\Windows PowerShell.lnk" />
                    <start:DesktopApplicationTile Size="1x1" Column="4" Row="1" DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\Windows PowerShell\Windows PowerShell ISE.lnk" />
                    <start:DesktopApplicationTile Size="1x1" Column="5" Row="0" DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\System Tools\UWP File Explorer.lnk" />
                    <start:DesktopApplicationTile Size="1x1" Column="5" Row="1" DesktopApplicationLinkPath="%ALLUSERSPROFILE%\Microsoft\Windows\Start Menu\Programs\Accessories\Paint.lnk" />
                </start:Group>
            </defaultlayout:StartLayout>
        </StartLayoutCollection>
    </DefaultLayoutOverride>
</LayoutModificationTemplate>
"@
			If ($RemovedSystemApps -contains 'Microsoft.Windows.FileExplorer') { $LayoutModTemplate = $LayoutModTemplate -replace 'UWP File Explorer.lnk', 'File Explorer.lnk' }
			Else
			{
				$UWPShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
				$UWPShortcut = $UWPShell.CreateShortcut((GetPath -Path $InstallMount -Child 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\System Tools\UWP File Explorer.lnk'))
				$UWPShortcut.TargetPath = "%SystemRoot%\explorer.exe"
				$UWPShortcut.Arguments = "shell:AppsFolder\c5e2524a-ea46-4f67-841f-6a9465d9d515_cw5n1h2txyewy!App"
				$UWPShortcut.WorkingDirectory = "%SystemRoot%"
				$UWPShortcut.Description = "UWP File Explorer"
				$UWPShortcut.Save()
			}
			$LayoutModTemplate | Out-File -FilePath (GetPath -Path $InstallMount -Child 'Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml') -Encoding UTF8 -Force -ErrorAction Stop
		}
		Catch
		{
			Log -Error $OptimizedData.FailedCleanupStartMenu
			$OptimizeErrors.Add($Error[0])
			(GetPath -Path $InstallMount -Child 'Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml') | Purge -ErrorAction SilentlyContinue
		}
		Finally
		{
			[Void][Runtime.InteropServices.Marshal]::ReleaseComObject($UWPShell); Start-Sleep 3; Clear-Host
		}

		If ($DynamicParams.Count -gt 0)
		{
			Log -Info $OptimizedData.CreatingPackageSummaryLog
			$PackageLog = New-Item -Path $PackageLog -ItemType File -Force -ErrorAction SilentlyContinue
			If ($DynamicParams.WindowsStore) { "`tIntegrated Provisioned App Packages", (Get-AppxProvisionedPackage -Path $InstallMount | Select-Object -Property PackageName) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force -ErrorAction SilentlyContinue }
			If ($DynamicParams.DeveloperMode -or $DynamicParams.MicrosoftEdge -or $DynamicParams.DataDeduplication -or $DynamicParams.NetFx3) { "`tIntegrated Windows Packages", (Get-WindowsPackage -Path $InstallMount | Where-Object { $PSItem.PackageName -like "*DeveloperMode*" -or $PSItem.PackageName -like "*Internet-Browser*" -or $PSItem.PackageName -like "*Windows-FileServer-ServerCore*" -or $PSItem.PackageName -like "*Windows-Dedup*" -or $PSItem.PackageName -like "*NetFx3*" } | Select-Object -Property PackageName, PackageState) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force -ErrorAction SilentlyContinue }
			If ($DynamicParams.InstallDrivers) { "`tIntegrated Drivers (Install)", (Get-WindowsDriver -Path $InstallMount | Select-Object -Property ProviderName, ClassName, BootCritical, Version | Sort-Object -Property ClassName | Format-Table -AutoSize) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force -ErrorAction SilentlyContinue }
			If ($DynamicParams.BootDrivers) { "`tIntegrated Drivers (Boot)", (Get-WindowsDriver -Path $BootMount | Select-Object -Property ProviderName, ClassName, BootCritical, Version | Sort-Object -Property ClassName | Format-Table -AutoSize) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force -ErrorAction SilentlyContinue }
			If ($DynamicParams.RecoveryDrivers) { "`tIntegrated Drivers (Recovery)", (Get-WindowsDriver -Path $RecoveryMount | Select-Object -Property ProviderName, ClassName, BootCritical, Version | Sort-Object -Property ClassName | Format-Table -AutoSize) | Out-File -FilePath $PackageLog.FullName -Append -Encoding UTF8 -Force -ErrorAction SilentlyContinue }
		}

		If ((Repair-WindowsImage -Path $InstallMount -CheckHealth).ImageHealthState -eq 'Healthy')
		{
			Log -Info $OptimizedData.PostOptimizedImageHealthHealthy
			@"
This $($InstallInfo.Name) installation was optimized with $($OptimizeOffline.BaseName) version $($ManifestData.ModuleVersion)
on $(Get-Date -UFormat "%m/%d/%Y at %r")
"@ | Out-File -FilePath (GetPath -Path $InstallMount -Child Optimize-Offline.txt) -Encoding Unicode -Force -ErrorAction SilentlyContinue
			Start-Sleep 3
		}
		Else
		{
			Log -Error $OptimizedData.PostOptimizedImageHealthCorrupted
			Stop-Optimize
		}

		If ($DynamicParams.Boot)
		{
			Try
			{
				Invoke-Cleanup Boot
				$DismountBootParams = @{
					Path             = $BootMount
					Save             = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					ErrorAction      = 'Stop'
				}
				Log -Info ($OptimizedData.SavingDismountingImage -f $BootInfo.Name)
				[Void](Dismount-WindowsImage @DismountBootParams)
			}
			Catch
			{
				Log -Error ($OptimizedData.FailedSavingDismountingImage -f $BootInfo.Name)
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
		}

		If ($DynamicParams.Recovery)
		{
			Try
			{
				Invoke-Cleanup Recovery
				$DismountRecoveryParams = @{
					Path             = $RecoveryMount
					Save             = $true
					ScratchDirectory = $ScratchFolder
					LogPath          = $DISMLog
					ErrorAction      = 'Stop'
				}
				Log -Info ($OptimizedData.SavingDismountingImage -f $RecoveryInfo.Name)
				[Void](Dismount-WindowsImage @DismountRecoveryParams)
			}
			Catch
			{
				Log -Error ($OptimizedData.FailedSavingDismountingImage -f $RecoveryInfo.Name)
				$OptimizeErrors.Add($Error[0])
				Stop-Optimize
			}
		}

		If ($DynamicParams.Boot)
		{
			Try
			{
				Log -Info ($OptimizedData.RebuildingExportingImage -f $BootInfo.Name)
				Get-WindowsImage -ImagePath $BootWim | ForEach-Object -Process {
					$ExportBootParams = @{
						SourceImagePath      = $BootWim
						SourceIndex          = $PSItem.ImageIndex
						DestinationImagePath = '{0}\boot.wim' -f $WorkFolder
						CheckIntegrity       = $true
						ScratchDirectory     = $ScratchFolder
						LogPath              = $DISMLog
						ErrorAction          = 'Stop'
					}
					[Void](Export-WindowsImage @ExportBootParams)
				}
				Get-ChildItem -Path $WorkFolder -Filter boot.wim | Move-Item -Destination $BootWim -Force
			}
			Catch
			{
				Log -Error ($OptimizedData.FailedRebuildingExportingImage -f $BootInfo.Name)
				$OptimizeErrors.Add($Error[0])
				Start-Sleep 3
			}
		}

		If ($DynamicParams.Recovery)
		{
			Try
			{
				$ExportRecoveryParams = @{
					SourceImagePath      = $RecoveryWim
					SourceIndex          = 1
					DestinationImagePath = '{0}\winre.wim' -f $WorkFolder
					CheckIntegrity       = $true
					ScratchDirectory     = $ScratchFolder
					LogPath              = $DISMLog
					ErrorAction          = 'Stop'
				}
				Log -Info ($OptimizedData.RebuildingExportingImage -f $RecoveryInfo.Name)
				[Void](Export-WindowsImage @ExportRecoveryParams)
				Get-ChildItem -Path $WorkFolder -Filter winre.wim | Move-Item -Destination $WinREPath -Force
			}
			Catch
			{
				Log -Error ($OptimizedData.FailedRebuildingExportingImage -f $RecoveryInfo.Name)
				$OptimizeErrors.Add($Error[0])
				Start-Sleep 3
			}
		}

		Try
		{
			Invoke-Cleanup Install
			$DismountInstallParams = @{
				Path             = $InstallMount
				Save             = $true
				ScratchDirectory = $ScratchFolder
				LogPath          = $DISMLog
				ErrorAction      = 'Stop'
			}
			Log -Info ($OptimizedData.SavingDismountingImage -f $InstallInfo.Name)
			[Void](Dismount-WindowsImage @DismountInstallParams)
		}
		Catch
		{
			Log -Error ($OptimizedData.FailedSavingDismountingImage -f $InstallInfo.Name)
			$OptimizeErrors.Add($Error[0])
			Stop-Optimize
		}

		Try
		{
			$CompressionType = Get-CompressionType -ErrorAction Stop
		}
		Catch
		{
			Do
			{
				$CompressionList = @('Solid', 'Maximum', 'Fast', 'None') | Select-Object -Property @{ Label = 'Compression'; Expression = { ($PSItem) } } | Out-GridView -Title "Select Final Image Compression." -OutputMode Single
				$CompressionType = $CompressionList | Select-Object -ExpandProperty Compression
			}
			While ($CompressionList.Length -eq 0)
		}

		Try
		{
			Log -Info ($OptimizedData.RebuildingExportingCompressed -f $InstallInfo.Name, $CompressionType)
			Switch ($CompressionType)
			{
				'Solid'
				{
					$SolidImage = Compress-Solid
					If ($SolidImage.Exists) { $InstallWim | Purge; $ImageFiles = @('install.esd', 'boot.wim') }
					Else { $ImageFiles = @('install.wim', 'boot.wim'); Throw }
				}
				Default
				{
					$ExportInstallParams = @{
						SourceImagePath      = $InstallWim
						SourceIndex          = $ImageIndex
						DestinationImagePath = '{0}\install.wim' -f $WorkFolder
						CompressionType      = $CompressionType
						CheckIntegrity       = $true
						ScratchDirectory     = $ScratchFolder
						LogPath              = $DISMLog
						ErrorAction          = 'Stop'
					}
					[Void](Export-WindowsImage @ExportInstallParams)
					Get-ChildItem -Path $WorkFolder -Filter install.wim | Move-Item -Destination $InstallWim -Force
					$ImageFiles = @('install.wim', 'boot.wim')
				}
			}
		}
		Catch
		{
			Log -Error ($OptimizedData.FailedRebuildingExportingCompressed -f $InstallInfo.Name, $CompressionType)
			$OptimizeErrors.Add($Error[0])
			Start-Sleep 3
		}
		Finally
		{
			[Void](Clear-WindowsCorruptMountPoint)
		}

		If (Get-ChildItem -Path $WorkFolder -Include InstallInfo.xml, CurrentVersion.xml -Recurse -File)
		{
			Try
			{
				$InstallInfo = Get-ImageData -Update -ErrorAction Stop
			}
			Catch
			{
				Log -Error ($OptimizedData.FailedToUpdateImageMetadata -f (GetPath -Path $InstallWim -Split Leaf))
				$OptimizeErrors.Add($Error[0])
				Start-Sleep 3
			}
		}
		Else
		{
			Log -Error ($OptimizedData.MissingRequiredDataFiles -f (GetPath -Path $InstallWim -Split Leaf))
			Start-Sleep 3
		}

		If ($ISOMedia.Exists)
		{
			Log -Info $OptimizedData.OptimizingInstallMedia
			Optimize-InstallMedia
			Get-ChildItem -Path $ImageFolder -Include $ImageFiles -Recurse | Move-Item -Destination (GetPath -Path $ISOMedia.FullName -Child sources) -Force -ErrorAction SilentlyContinue
			If ($ISO)
			{
				If ($ISO -eq 'Prompt' -and (!(Test-Path -Path (GetPath -Path $ISOMedia.FullName -Child 'efi\Microsoft\boot\efisys.bin')))) { Log -Error "Missing the required efisys.bin bootfile for ISO creation." }
				ElseIf ($ISO -eq 'No-Prompt' -and (!(Test-Path -Path (GetPath -Path $ISOMedia.FullName -Child 'efi\Microsoft\boot\efisys_noprompt.bin')))) { Log -Error "Missing the required efisys_noprompt.bin bootfile for ISO creation." }
				Else
				{
					Try
					{
						Log -Info ($OptimizedData.CreatingISO -f $ISO)
						$ISOFile = New-ISOMedia -BootType $ISO -ErrorAction Stop
					}
					Catch
					{
						Log -Error ($OptimizedData.FailedCreatingISO -f $ISO)
						$OptimizeErrors.Add($Error[0])
						Start-Sleep 3
					}
				}
			}
		}

		Try
		{
			Log -Info $OptimizedData.FinalizingOptimizations
			$ErrorActionPreference = 'SilentlyContinue'
			$SaveDirectory = Create -Path (GetPath -Path $OptimizeOffline.Directory -Child Optimize-Offline_$((Get-Date).ToString('yyyy-MM-ddThh.mm.ss'))) -PassThru
			If ($ISOFile) { Move-Item -Path $ISOFile -Destination $SaveDirectory.FullName }
			Else
			{
				If ($ISOMedia.Exists) { Move-Item -Path $ISOMedia.FullName -Destination $SaveDirectory.FullName }
				Else { Get-ChildItem -Path $ImageFolder -Include $ImageFiles -Recurse | Move-Item -Destination $SaveDirectory.FullName }
			}
		}
		Finally
		{
			$Timer.Stop()
			Start-Sleep 5
			Log -Info ($OptimizedData.OptimizationsCompleted -f $OptimizeOffline.BaseName, $Timer.Elapsed.Minutes.ToString(), $OptimizeErrors.Count) -Finalized
			@($DISMLog, (GetPath -Path $Env:SystemRoot -Child 'Logs\DISM\dism.log')) | Purge
			If ($OptimizeErrors.Count -gt 0) { Export-ErrorLog }
			[Void](Get-ChildItem -Path $LogFolder -Include *.log -Recurse | Compress-Archive -DestinationPath (GetPath -Path $SaveDirectory.FullName -Child OptimizeLogs.zip) -CompressionLevel Fastest)
			($InstallInfo | Out-String).Trim() | Out-File -FilePath (GetPath -Path $SaveDirectory.FullName -Child WimFileInfo.xml) -Encoding UTF8
			$TempDirectory | Purge
		}
		#endregion Image Finalization
	}
	End
	{
		#region Restore Session Defaults
		$ErrorActionPreference = $DefaultErrorActionPreference
		((Compare-Object -ReferenceObject (Get-Variable).Name -DifferenceObject $DefaultVariables).InputObject).ForEach{ Remove-Variable -Name $PSItem -ErrorAction Ignore }
		$Error.Clear()
		#endregion Restore Session Defaults
	}
}
Export-ModuleMember -Function Optimize-Offline
# SIG # Begin signature block
# MIIMDAYJKoZIhvcNAQcCoIIL/TCCC/kCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUy6iEWSPYMDYyqHyUaLQO6oIo
# yUqgggjkMIIDZTCCAk2gAwIBAgIQcvzm3AoNiblMifO61mXaqjANBgkqhkiG9w0B
# AQsFADBFMRQwEgYKCZImiZPyLGQBGRYEVEVDSDEVMBMGCgmSJomT8ixkARkWBU9N
# TklDMRYwFAYDVQQDEw1PTU5JQy5URUNILUNBMB4XDTE5MDUxNTEyMDYwN1oXDTI0
# MDUxNTEyMTYwN1owRTEUMBIGCgmSJomT8ixkARkWBFRFQ0gxFTATBgoJkiaJk/Is
# ZAEZFgVPTU5JQzEWMBQGA1UEAxMNT01OSUMuVEVDSC1DQTCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAMivWQ61s2ol9vV7TTAhP5hy2CADYNl0C/yVE7wx
# 4eEeiVfiFT+A78GJ4L1h2IbTM6EUlGAtxlz152VFBrY0Hm/nQ1WmrUrneFAb1kTb
# NLGWCyoH9ImrZ5l7NCd97XTZUYsNtbix3nMqUuPPq+UA23pekolHBCpRoDdya22K
# XEgFhOdWfKWsVSCZYiQZyT/moXO2aCmgILq0qtNvNS24grVXTX+qgr1OeiOIF+0T
# SB1oYqTNvROUJ4D6sv4Ap5hJ5PFYmbQrBnytEBGQwXyumQGoK8l/YUBbScsoSjNH
# +GkJMVox7GZObEGf1aLNMCXh7bjpXFw/RJgvBmypkWPIdOUCAwEAAaNRME8wCwYD
# VR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFGzmcuTlwYRYLA1E
# /XGZHHp2+GqTMBAGCSsGAQQBgjcVAQQDAgEAMA0GCSqGSIb3DQEBCwUAA4IBAQCk
# iQqEJdY3YdQWWM3gBqfgJOaqA4oMTAJCIwj+N3zc4UUChaMOq5kAKRRLMtXOv9fH
# 7L0658kt0+URQIB3GrtkV/h3VYdwACWQLGHvGfZ2paFQTF7vT8KA4fi8pkfRoupg
# 4PZ+drXL1Nq/Nbsr0yaakm2VSlij67grnMOdYBhwtf919qQZdvodJQKL+XipjmT3
# tapbg0FMnugL6vhsB6H8nGWO8szHws2UkiWXSmnECJLYQxZ009do3L0/J4BJvak5
# RUzNcZJIuTnifEIax68UcKHU8bFAaiz5Zns74d0qqZx6ZctYLlPI58mhSn9pohoL
# ozlL4YdE7lQ8EDTiKZTIMIIFdzCCBF+gAwIBAgITGgAAAAgLhnXW+w68VgAAAAAA
# CDANBgkqhkiG9w0BAQsFADBFMRQwEgYKCZImiZPyLGQBGRYEVEVDSDEVMBMGCgmS
# JomT8ixkARkWBU9NTklDMRYwFAYDVQQDEw1PTU5JQy5URUNILUNBMB4XDTE5MDUx
# ODE5MDQ1NloXDTIwMDUxNzE5MDQ1NlowUzEUMBIGCgmSJomT8ixkARkWBFRFQ0gx
# FTATBgoJkiaJk/IsZAEZFgVPTU5JQzEOMAwGA1UEAxMFVXNlcnMxFDASBgNVBAMT
# C0JlblRoZUdyZWF0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvnkk
# jYlPGAeAApx5Qgn0lbHLI2jywWcsMl2Aff0FDH+4IemQQSQWsU+vCuunrpqvCXMB
# 7yHgecxw37BWnbfEpUyYLZAzuDUxJM1/YQclhH7yOb0GvhHaUevDMCPaqFT1/QoS
# 4PzMim9nj1CU7un8QVTnUCSivC88kJnvBA6JciUoRGU5LAjLDhrMa+v+EQjnkErb
# Y0L3bi3D+ROA23D1oS6nuq27zeRHawod1wscT+BYGiyP/7w8u/GQdGZPeNdw0168
# XCEicDUEiB/s4TI4dCr+0B80eI/8jHTYs/LFj+v6QETiQChR5Vk8lsS3On1LI8Fo
# 8Ki+PPgYCdScxiYNfQIDAQABo4ICUDCCAkwwJQYJKwYBBAGCNxQCBBgeFgBDAG8A
# ZABlAFMAaQBnAG4AaQBuAGcwEwYDVR0lBAwwCgYIKwYBBQUHAwMwDgYDVR0PAQH/
# BAQDAgeAMB0GA1UdDgQWBBQQg/QKzp8JFAJtalEPhIrNKV7A2jAfBgNVHSMEGDAW
# gBRs5nLk5cGEWCwNRP1xmRx6dvhqkzCByQYDVR0fBIHBMIG+MIG7oIG4oIG1hoGy
# bGRhcDovLy9DTj1PTU5JQy5URUNILUNBLENOPUFOVUJJUyxDTj1DRFAsQ049UHVi
# bGljJTIwS2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlv
# bixEQz1PTU5JQyxEQz1URUNIP2NlcnRpZmljYXRlUmV2b2NhdGlvbkxpc3Q/YmFz
# ZT9vYmplY3RDbGFzcz1jUkxEaXN0cmlidXRpb25Qb2ludDCBvgYIKwYBBQUHAQEE
# gbEwga4wgasGCCsGAQUFBzAChoGebGRhcDovLy9DTj1PTU5JQy5URUNILUNBLENO
# PUFJQSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1D
# b25maWd1cmF0aW9uLERDPU9NTklDLERDPVRFQ0g/Y0FDZXJ0aWZpY2F0ZT9iYXNl
# P29iamVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwMQYDVR0RBCowKKAm
# BgorBgEEAYI3FAIDoBgMFkJlblRoZUdyZWF0QE9NTklDLlRFQ0gwDQYJKoZIhvcN
# AQELBQADggEBAEyyXCN8L6z4q+gFjbm3B3TvuCAlptX8reIuDg+bY2Bn/WF2KXJm
# +FNZakUKccesxl2XUJo2O7KZBKKjZYMwEBK7NhTOvC50VupJc0p6aXrMrcOnAjAn
# NrjWbKYmc6bG7uCzuEBPlJVmnhdRLgRJKfJDAfXPWkYebV666WnggugL4ROOYtOY
# 3J8j/2cyYE6OD5YTl1ydnYzyNUeZq2IVfxw5BK83lVK5uuneg+4QQaUNWBU5mtIa
# 6t748F1ZEQm3UNk8ImFKWp4dsgAHpPC5wZo/BAMO8PP8BW3+6yvewWnUAGTU4f07
# b1SjZsLcQ6D0eCcFD+7I7MkcSz2ARu6wUOcxggKSMIICjgIBATBcMEUxFDASBgoJ
# kiaJk/IsZAEZFgRURUNIMRUwEwYKCZImiZPyLGQBGRYFT01OSUMxFjAUBgNVBAMT
# DU9NTklDLlRFQ0gtQ0ECExoAAAAIC4Z11vsOvFYAAAAAAAgwCQYFKw4DAhoFAKCC
# AQswGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwG
# CisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFIng+w+ucZuLdiFPMWQhJJik//4C
# MIGqBgorBgEEAYI3AgEMMYGbMIGYoGKAYABXAGkAbgBkAG8AdwBzACAAMQAwACAA
# bwBmAGYAbABpAG4AZQAgAGkAbQBhAGcAZQAgAG8AcAB0AGkAbQBpAHoAYQB0AGkA
# bwBuACAAZgByAGEAbQBlAHcAbwByAGsALqEygDBodHRwczovL2dpdGh1Yi5jb20v
# RHJFbXBpcmljaXNtL09wdGltaXplLU9mZmxpbmUwDQYJKoZIhvcNAQEBBQAEggEA
# ZssPwhOka+MKNNRoOXKQPblXN8VL/TJr7nKXPH7OxqrHOUpti1NMaffz7Ve4FuzD
# PxHJvHylcU76QXaN+J6CY0FEgwwLWSmuTV8NHQbbk60pZj+4vrW1Ghct0DIYw5d7
# HUn5TSEaIKIcwHw3M3X56+LPbJyFexYvfXe+BuDkAWemqfaQthyKZR6PYa4+PGtR
# TgHzkvlvBc1Gw4iCoE7BmU8zu6IrgLXNRjfjzlGyFa+aR47pSC0lD0kuA+qkFDNE
# U1+hxsTQJaI9gTfjz2YLaGK++WwJETtcZkvhT63lc+b+XiJAfObHCSbQQtSpb2Wv
# AYOn8jd+3CcAqyt1zZw9/A==
# SIG # End signature block
