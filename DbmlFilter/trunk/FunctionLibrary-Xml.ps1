function Dump-Xml ([xml]$doc)
{
	[System.Xml.XmlWriterSettings]$writerSettings = new-object System.Xml.XmlWriterSettings;
	$writerSettings.set_Indent($TRUE);
	$writerSettings.set_NewLineHandling([System.Xml.NewLineHandling]::Replace);
	$writerSettings.set_CloseOutput($TRUE);
	
	$local:outputStream = new-object System.IO.StringWriter;
	[System.Xml.XmlWriter]$local:writer = [System.Xml.XmlWriter]::Create($outputStream, $writerSettings);
	
	$doc.Save($writer);
	$writer.Flush();
	$writer.Close();
	$outputStream.Close();
	
	$outputStream.ToString();
}

function Read-Xml ([System.IO.FileInfo]$path)
{
	[System.Xml.XmlReader]$reader = [System.Xml.XmlReader]::Create($path.FullName);
	[System.Xml.XmlDocument]$doc = new-object System.Xml.XmlDocument;
	$doc.set_PreserveWhitespace($TRUE);
	$doc.Load($reader);
	
	$reader.Close();
	
	return $doc;
}
 