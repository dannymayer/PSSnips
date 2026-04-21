# PSSnips — Abstract remote provider base class

class RemoteProvider {
    [string] $ProviderName = ''

    [bool]             IsConfigured()                                                                   { throw [System.NotImplementedException]::new('IsConfigured') }
    [PSCustomObject[]] ListRemote([string]$filter)                                                      { throw [System.NotImplementedException]::new('ListRemote') }
    [PSCustomObject]   GetRemoteById([string]$id)                                                       { throw [System.NotImplementedException]::new('GetRemoteById') }
    [PSCustomObject]   CreateRemote([string]$title, [string]$content, [string]$ext, [bool]$isPrivate)   { throw [System.NotImplementedException]::new('CreateRemote') }
    [void]             UpdateRemote([string]$id, [string]$fileKey, [string]$content)                    { throw [System.NotImplementedException]::new('UpdateRemote') }
    [void]             DeleteRemote([string]$id)                                                        { throw [System.NotImplementedException]::new('DeleteRemote') }
    [PSCustomObject]   SyncRemote([string]$localName, [string]$direction)                               { throw [System.NotImplementedException]::new('SyncRemote') }
}
