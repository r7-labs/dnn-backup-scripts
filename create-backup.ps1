Param (
	[String]$Target,
	[String]$TargetDirectory,
	[Int32]$MaxBackups
)

$BackupDirectory = "B:\Backup"
$DbDirectory = "W:\Database"
$DbLogDirectory = "W:\Database"
$DbServer = "(local)"
$DbName = "Dnn804"

if (-not (Test-Path -Path $TargetDirectory)) {
	Write-Error "Target directory '$TargetDirectory' not exists"
}

if (-not (Test-Path -Path $BackupDirectory)) {
	Write-Error "Backup directory '$BackupDirectory' not exists"
}

if (-not (Test-Path -Path $DbDirectory)) {
	Write-Error "Database directory '$DbDirectory' not exists"
}

if (-not (Test-Path -Path $DbLogDirectory)) {
	Write-Error "Database log directory '$DbLogDirectory' not exists"
}

if ($Target -eq "dotnetnuke") {
	
	## Backup IIS configuration

	# create target config directory
	$TargetConfigDirectory = Join-Path $TargetDirectory "_Backup_9SH26GA7"
	New-Item -ItemType Directory -Force -Path $TargetConfigDirectory

	$appCmd = Join-Path $Env:windir "\system32\inetsrv\appcmd.exe"
	$configDirectory = Join-Path $Env:windir "\system32\inetsrv\backup\iis_config"

	$deleteBackupArgs = 'delete', 'backup', '"iis_config"'
	$addBackupArgs = 'add', 'backup', '"iis_config"'

	& $appCmd $deleteBackupArgs
	& $appCmd $addBackupArgs

	Copy-Item -Recurse -Force $configDirectory $TargetConfigDirectory

	## Backup admin scripts and settings

	Copy-Item -Recurse -Force "C:\admin" $TargetConfigDirectory

	# set "Hidden" attribute on backup dir 
	Get-ChildItem $TargetConfigDirectory -Recurse | foreach {$_.Attributes = 'Hidden'}

	## Backup database to the App_Data folder

	Invoke-Sqlcmd -Query "BACKUP DATABASE $DbName TO DISK='$TargetDirectory\App_Data\$DbName.bak' WITH FORMAT;" -ServerInstance $DbServer -Verbose
	if ( -not $? ) {
		Write-Error "Database backup failed"
	}

	## Cleanup database

	Invoke-Sqlcmd -Query "EXECUTE dbo.r7_Dnn_Cleanup;" -ServerInstance $DbServer -Database $DbName -Verbose
	if ( -not $? ) {
		Write-Warning "Database cleanup failed"
	}

} # end $Target -eq "dotnetnuke" 

## Making an archive

$today = Get-Date -UFormat '%y%m%d'

$archiveArgs = 'a', '-bd', '-t7z', '-mx0', '-mmt=off', '-r', '-y', "$Target-$today.7z", "$TargetDirectory\*"
$archiveCmd = "C:\Program Files\7-Zip\7z.exe"

Push-Location -Path $BackupDirectory

& $archiveCmd $archiveArgs

if ( -not $? ) {
	# 7-Zip will return 1 in case of warning, but exit codes from 2 are fatal errors
	if ( $LastExitCode -gt 1 ) {
		Write-Error "7-Zip exited with code $LastExitCode"
	}
}

## Calculate MD5 checksum

# TODO: Use PowerShell script and SHA256

$checkSumArgs = '-wp', '-add', "$Target-$today.7z"
$checkSumCmd = "W:\Admin\fciv\fciv.exe"
& $checkSumCmd $checkSumArgs | Out-File "$Target-$today.7z.md5"
	
if ( -not $? ) {
	Write-Error "Fciv exited with code $LastExitCode"
}

## Remove oldest backups, if too many

$backups = Get-ChildItem -Path ".\*" -Include "$Target-*.7z" | Sort-Object Name

for ($i = 0; $i -lt ($backups.Count - $MaxBackups); $i++) {
	Remove-Item $backups[$i] -Force
	$checkSumFile = $backups[$i].Name + ".md5"
	if (Test-Path -Path $checkSumFile) {
		Remove-Item -Path $checkSumFile -Force
	}
}

Pop-Location

