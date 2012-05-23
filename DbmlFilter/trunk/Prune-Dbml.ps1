param
(
	$DBML = @(Throw "Input DBML file path parameter must be specified"),
	[hashtable]$REMOVETABLES = @{},
	[hashtable]$RENAMETABLES = @{},
	[hashtable]$RENAMEASSOCIATIONS = @{},
	[string]$ENTITYBASE = $null,
    [string]$ACCESSMODIFIER = $null,
	[bool]$KEEPSCHEMANAMES = $true
)

if (-not (Test-Path ($DBML)))
{
	$DBML = Join-Path -path $pwd -childpath $DBML;
}

if (-not (Test-Path ($DBML)))
{
	Throw "DBML file path cannot be found or resolved";
}

$dbmlFileInfo = Get-Item -path $DBML;

[xml]$local:doc = Read-Xml $dbmlFileInfo;

function Count-Tables ([xml]$doc)
{
	[int]$local:count = 0;
	$temp = $doc.Database.Table | ForEach-Object { $count = $count + 1; }
	return $count;
}

function Count-Associations ([xml]$doc)
{
	[int]$local:count = 0;
	$temp = $doc.Database.Table `
					| Where-Object { $_.Type.Association -ne $null } `
					| ForEach-Object { $_.Type.Association; } `
					| ForEach-Object { $count = $count + 1; }
						
	return $count;
}

Write-Debug ("Was - " + (Count-Tables($doc)) + " tables in generated DBML");
Write-Debug ("Was - " + (Count-Associations($doc)) + " associations in generated DBML");
Write-Debug ("Need to clean table names? " + -not ($KEEPSCHEMANAMES));

# Set the EntityBase attribute into the DBML if defined in parameter
if (-not [String]::IsNullOrEmpty($ENTITYBASE))
{
	$doc.Database.SetAttribute("EntityBase", $ENTITYBASE);
}
elseif ($doc.Database.EntityBase -ne $null)
{
	$doc.Database.RemoveChild($doc.Database.EntityBase);
}

if (-not [String]::IsNullOrEmpty($ACCESSMODIFIER))
{
	$doc.Database.SetAttribute("AccessModifier", $ACCESSMODIFIER);
}

#$REMOVETABLES.Keys | ForEach-Object { Write-Debug $_ };
#Write-Debug ("Contains " + $REMOVETABLES.Contains("TdsLevel"));

# Remove nodes that don't belong
# Also, put any hits into a collection for fixing up associations later
[int]$local:count = 0;
$removedTypeMap = @{};
$tableNodesRemoved = $doc.Database.Table `
					| ForEach-Object { $_; } `
					| Where-Object { $REMOVETABLES.Contains($_.Name) } `
					| ForEach-Object `
					  { `
					  	$removedTypeMap.Add($_.Type.Name, $_.Name); `
						$_ = $doc.Database.RemoveChild($_); `
						$count = $count + 1; `
						$_; `
					  };

Write-Debug ("Removed - " + $count + " tables from generated DBML");

# Remove any associations on other tables which reference a removed type
$count = 0;
$associationNodesWithTypesRemoved = $doc.Database.Table `
					| Where-Object { $_.Type.Association -ne $null } `
					| ForEach-Object { $_.Type.Association; } `
					| Where-Object { $removedTypeMap[$_.Type] -ne $null } `
					| ForEach-Object { $_ } `
					| Where-Object {  $REMOVETABLES[$removedTypeMap[$_.Type]] -eq $null } `
					| ForEach-Object `
					  { `
					  	$_ = $_.get_ParentNode().RemoveChild($_); `
						$count = $count + 1; `
						$_; `
					  };

Write-Debug ("Removed - " + $count + " additional associations for removed tables from generated DBML");

# Rename the types of any associations on other tables which reference a removed type
$count = 0;
$associationNodesWithTypesRemovedButRenamed = $doc.Database.Table `
					| Where-Object { $_.Type.Association -ne $null } `
					| ForEach-Object { $_.Type.Association; } `
					| Where-Object { $removedTypeMap[$_.Type] -ne $null } `
					| ForEach-Object { $_ } `
					| Where-Object {  $REMOVETABLES[$removedTypeMap[$_.Type]] -ne $null } `
					| ForEach-Object `
					  { `
					  	$_.Type = $REMOVETABLES[$removedTypeMap[$_.Type]]; `
						$count = $count + 1; `
						$_; `
					  };

Write-Debug ("Fixed - " + $count + " additional associations for removed tables from generated DBML");

# Find nodes for tables which need to be renamed
$count = 0;
$tableNodesToRename = $doc.Database.Table `
					| ForEach-Object { $_; } `
					| Where-Object { $RENAMETABLES[$_.Name] -ne $null };

$renamedTypeMap = @{};
$renamedMemberMap = @{};
# If any found, rename the Type names and also the members
# Also, put any hits into a collection for fixing up other associations
if ($tableNodesToRename -ne $null)
{
	$tableNodesToRename `
					| ForEach-Object `
					  { `
					  	$newName = $RENAMETABLES[$_.Name].Type; `
						$renamedTypeMap.Add($_.Type.Name, $newName); `
						$_.Type.Name = $newName; `
						$count = $count + 1; `
						$_; `
					  } `
					| Out-Null;
	$tableNodesToRename `
					| ForEach-Object `
					  { `
					  	$newName = $RENAMETABLES[$_.Name].Member; `
						$renamedMemberMap.Add($_.Member, $newName); `
						$_.Member = $newName; `
						$_; `
					  } `
					| Out-Null;
}

Write-Debug ("Renamed - " + $count + " tables from generated DBML");

# Find any associations on other tables which reference a renamed type
$count = 0;
$associationNodesWithTypesRenamed = $doc.Database.Table `
					| Where-Object { $_.Type.Association -ne $null } `
					| ForEach-Object { $_.Type.Association; } `
					| Where-Object { $renamedTypeMap[$_.Type] -ne $null} `
					| ForEach-Object `
					  { `
					  	$_.Type = $renamedTypeMap[$_.Type]; `
						$count = $count + 1; `
						$_; `
					  };

if ($associationNodesWithTypesRenamed -ne $null)
{
	# Fix up member names for any associations on other tables which are Foreign Key associations and reference a renamed type
	$associationNodesWithTypesRenamed `
					| Where-Object { $renamedTypeMap[$_.Member] -ne $null -and $_.IsForeignKey -eq "true"} `
					| ForEach-Object { $_.Member = $renamedTypeMap[$_.Member]; $_; } `
					| Out-Null;

	# Fix up member names for any associations on other tables which are Subset associations and reference a renamed member
	$associationNodesWithTypesRenamed `
					| Where-Object { $renamedMemberMap[$_.Member] -ne $null -and $_.IsForeignKey -eq $null } `
					| ForEach-Object { $_.Member = $renamedMemberMap[$_.Member]; $_; } `
					| Out-Null;

}

Write-Debug ("Renamed - " + $count + " associations for renamed tables from generated DBML");

# Find and rename any associations that need foreign key nodes renamed
$count = 0;
$associationFKNodesRenamed = $doc.Database.Table `
					| Where-Object { $_.Type.Association -ne $null } `
					| ForEach-Object { $_.Type.Association; } `
					| Where-Object { $RENAMEASSOCIATIONS[$_.Name] -ne $null -and $_.IsForeignKey -eq "true"} `
					| ForEach-Object `
					  { `
					  	if (-not [String]::IsNullOrEmpty($RENAMEASSOCIATIONS[$_.Name].FKMember)) `
						{ `
					  	  $_.Member = $RENAMEASSOCIATIONS[$_.Name].FKMember; `
						} `
						else `
						{ `
						  $_ = $_.get_ParentNode().RemoveChild($_); `
						} `
						$count = $count + 1; `
						$_; `
					  };

Write-Debug ("Renamed - " + $count + " associations with named foreign key members from generated DBML");

# Find and rename any associations that need member nodes renamed
$count = 0;
$associationSubsetNodesRenamed = $doc.Database.Table `
					| Where-Object { $_.Type.Association -ne $null } `
					| ForEach-Object { $_.Type.Association; } `
					| Where-Object { $RENAMEASSOCIATIONS[$_.Name] -ne $null -and $_.IsForeignKey -eq $null } `
					| ForEach-Object `
					  { `
						if (-not [String]::IsNullOrEmpty($RENAMEASSOCIATIONS[$_.Name].PluralMember)) `
						{ `
						  $_.Member = $RENAMEASSOCIATIONS[$_.Name].PluralMember; `
						} `
						else `
						{ `
						  $_ = $_.get_ParentNode().RemoveChild($_); `
						} `
						$count = $count + 1; `
						$_; `
					  };

Write-Debug ("Renamed - " + $count + " associations with named subset members from generated DBML");

function Remove-TableSchemaName([string]$tableName)
{
	$local:i = $tableName.LastIndexOf(".");
	if ($i -ge 0 -and $i -lt $tableName.Length - 1)
	{
		return $tableName.Substring($i + 1);
	}
	elseif ($i -eq $tableName.Length)
	{
		return [System.String]::Empty;
	}
	return $tableName;
}

if (-not ($KEEPSCHEMANAMES))
{
	$doc.Database.Table `
		| Where-Object { $_.Name -ne $null } `
		| ForEach-Object `
		{ `
			$local:name = Remove-TableSchemaName -tableName $_.Name;
			$_.Name = "$name"; `
		}
}

Write-Debug ("Now - " + (Count-Tables($doc)) + " tables in generated DBML");
Write-Debug ("Now - " + (Count-Associations($doc)) + " associations in generated DBML");

Dump-Xml $doc;