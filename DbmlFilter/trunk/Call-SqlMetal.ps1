param
(
	[string]$CONN = $null,
	[string]$DATABASE = $null,
	[string]$CONTEXT = ($DATABASE + "DataContext"),
	$DBML = (Join-Path -Path (Join-Path -Path $PWD -ChildPath "Domain") -ChildPath ($CONTEXT + ".dbml")),
	$CODE = $null,
	[string]$SERVER = ".",
	[boolean]$VIEWS = $FALSE,
	[string]$ENTITYBASE = "System.Object",
	[string]$NAMESPACE = ($DATABASE + ".Domain"), # Would like to do some sneaky stuff to get the organisation
	$CLEANERXML = $null, # Indicates and input XML file to use for cleaning DBML file
	$FUNCTIONLIBRARYPATH = $pwd # Indicates a path from current working directory to the function library scripts
)

if ([String]::IsNullOrEmpty($CONN) -and [String]::IsNullOrEmpty($DATABASE))
{
	Throw "The 'database' or 'conn' parameter must be provided."
}

# Replace with value of SilentlyContinue to hide debug messages including SqlMetal.exe output.
$DebugPreference = "Continue";

# Load up all functions from our library.
if (-not (Test-Path $FUNCTIONLIBRARYPATH)){ Throw "FunctionLibraryPath argument - Path cannot be found" };
Get-ChildItem $FUNCTIONLIBRARYPATH -Include FunctionLibrary-*.ps1 -Recurse | ForEach-Object { . $_; } | Out-Null;

Write-Debug "** Generating DBML file **"
# Generate a stub file in order to ensure path is also built
New-Item -Path $DBML -type file -Force | Out-Null;

# Generate original DBML file
# NOTE: Couldn't work out how to get the arguments to pass in as a variable string. PowerShell seems to mess with the formatting.
if ([String]::IsNullOrEmpty($CONN))
{
	if ($VIEWS)
	{ (& sqlmetal /server:$SERVER /database:$DATABASE /pluralize /namespace:$NAMESPACE /context:$CONTEXT /dbml:$DBML /entitybase:$ENTITYBASE /views) | Write-Debug }
	else
	{ (& sqlmetal /server:$SERVER /database:$DATABASE /pluralize /namespace:$NAMESPACE /context:$CONTEXT /dbml:$DBML /entitybase:$ENTITYBASE) | Write-Debug } 
}
else
{
	if ($VIEWS)
	{ (& sqlmetal /conn:$CONN /pluralize /namespace:$NAMESPACE /context:$CONTEXT /dbml:$DBML /entitybase:$ENTITYBASE /views) | Write-Debug }
	else
	{ (& sqlmetal /conn:$CONN /pluralize /namespace:$NAMESPACE /context:$CONTEXT /dbml:$DBML /entitybase:$ENTITYBASE) | Write-Debug } 
}

Check-LastExitCode -CleanupScript { Throw "SqlMetal DBML file generation failed.`n`nCall stack:`n`n$(Get-CallStack)"; }

# Test and/or attempt to resolve cleaning XML file
if (-not [String]::IsNullOrEmpty($CLEANERXML))
{
	if (-not (Test-Path $CLEANERXML))
	{
		$CLEANERXML = Resolve-Path -Path $CLEANERXML;
	}
	
	if (Test-Path $CLEANERXML)
	{
		Write-Debug "** Reading clean settings **"
		
		$ReadDbmlCleanerXmlScript = Join-Path -Path (Get-ScriptDirectory) -ChildPath "Read-DbmlCleanerXml.ps1";
		if (-not (Test-Path $ReadDbmlCleanerXmlScript))
		{ Throw "Read-DbmlCleanerXml.ps1 script must be located in the same directory as Call-SqlMetal.ps1 script but it was not found."; }

		$PruneDbmlScript = Join-Path -Path (Get-ScriptDirectory) -ChildPath "Prune-Dbml.ps1";
		if (-not (Test-Path $PruneDbmlScript))
		{ Throw "Prune-Dbml.ps1 script must be located in the same directory as Call-SqlMetal.ps1 script but it was not found."; }
				
		$CleanerOutput = & $ReadDbmlCleanerXmlScript -CleanerXml $CLEANERXML;
		
		Write-Debug ("Read - " + $CleanerOutput["RemoveTables"].Count + " tables for removal");
		Write-Debug ("Read - " + $CleanerOutput["RenameTables"].Count + " tables for renaming");
		Write-Debug ("Read - " + $CleanerOutput["RenameAssociations"].Count + " asosciations for renaming");
		Write-Debug "";

		Write-Debug "** Cleaning generated DBML file **"

		& $PruneDbmlScript `
						-dbml $DBML `
						-removeTables $CleanerOutput["RemoveTables"] `
						-renameTables $CleanerOutput["RenameTables"] `
						-renameAssociations $CleanerOutput["RenameAssociations"] `
						| Out-File -FilePath ($DBML + ".tmp");
		
		Move-Item -Path ($DBML + ".tmp") -Destination $DBML -Force;
		
		Write-Debug "";
	}
}

# Build designer path if not defined
if ($DESIGNER -eq $null) { $DESIGNER = ($DBML.ToString().Remove($DBML.LastIndexOf(".")) + ".designer.cs"); }

Write-Debug "** Generating designer file **"
# Generate designer file
(& sqlmetal /code:$DESIGNER $DBML) | Write-Debug

Check-LastExitCode -CleanupScript { Throw "SqlMetal designer file generation failed`n`nCall stack:`n`n$(Get-CallStack)"; }
