param
(
	[string]$CLEANERXML = @(Throw "CleanerXml argument must be provided")
)

if (-not (Test-Path $CLEANERXML)) { Throw "CleanerXml argument - Path cannot be found" };

$xmlFileInfo = Get-Item -path $CLEANERXML;

[xml]$doc = Read-Xml $xmlFileInfo;

$KeepSchemaNames = $true;
if ($doc.Dbml.Tables.KeepSchemaNames -ne $null)
{
	$KeepSchemaNames = [System.Boolean]::Parse($doc.Dbml.Tables.KeepSchemaNames);
}

# Simple array of names of tables to remove.
$Remove = @{};
$temp = $doc.Dbml.Tables.Remove `
		| Where-Object { $_.Name -ne $null -and ( $_.KeepFk -eq $null -or $_.KeepFk -ne "true") } `
		| ForEach-Object { $Remove.Add($_.Name, $null); };

$temp = $doc.Dbml.Tables.Remove `
		| Where-Object { $_.Name -ne $null -and ($_.KeepFk -ne $null -and $_.KeepFk -eq "true" -and $_.NewFkType -ne $null) } `
		| ForEach-Object { $Remove.Add($_.Name, $_.NewFkType); };

# Keyed by name, sub dictionary with keys type and member.
$Rename = @{};
$temp = $doc.Dbml.Tables.Rename `
		| Where-Object { $_.Name -ne $null } `
		| ForEach-Object { $Rename.Add($_.Name, @{ Type = $_.Type; Member = $_.Member }) };

# Keyed by name, sub dictionary with keys FKMember and PluralMember.
$FixUp = @{};
$temp = $doc.Dbml.Associations.Rename `
		| Where-Object { $_.Name -ne $null } `
		| ForEach-Object { $FixUp.Add($_.Name, @{ FKMember = $_.FKMember; PluralMember = $_.PluralMember }) };

$Output = @{KeepSchemaNames = $KeepSchemaNames; RemoveTables = $Remove; RenameTables = $Rename; RenameAssociations = $FixUp;};
return $Output;