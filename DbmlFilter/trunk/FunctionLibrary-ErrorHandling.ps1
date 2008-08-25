
# From http://www.microsoft.com/communities/newsgroups/en-us/default.aspx?dg=microsoft.public.windows.powershell&tid=25aedbbf-bc81-4cb4-9175-adb6c1e2997e&cat=&lang=&cr=&sloc=&p=1
function Get-CallStack { 
	trap { continue } 
	1..100 | foreach { 
		$var = Get-Variable -scope $_ MyInvocation 
		$var.Value.PositionMessage #-replace "`n" 
	} 
} 

#-------------------------------------------------------------------- 
# Helper function to deal with legacy exe exit codes 
#-------------------------------------------------------------------- 
function Check-LastExitCode { 
	param ([int[]]$SuccessCodes = @(0), [scriptblock]$CleanupScript=$null) 

	if ($SuccessCodes -notcontains $LASTEXITCODE) { 
		if ($CleanupScript) { 
			"Executing cleanup script: $CleanupScript" 
			&$CleanupScript 
		}
		
		$OFS = $NL = [System.Environment]::get_NewLine();
		Throw "EXE RETURNED EXIT CODE ${LastExitCode}${NL}$(Get-CallStack)" 
	} 
}