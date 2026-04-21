# PSSnips — Abstract repository base class

class SnipRepositoryBase {
    # Subclasses override methods they implement.
    # Calling an unimplemented method throws NotImplementedException.

    [hashtable] GetIndex()                                                           { throw [System.NotImplementedException]::new('GetIndex') }
    [void]      SaveIndex([hashtable]$idx)                                           { throw [System.NotImplementedException]::new('SaveIndex') }
    [string]    GetSnipContent([string]$name)                                        { throw [System.NotImplementedException]::new('GetSnipContent') }
    [void]      SaveSnipContent([string]$name, [string]$content, [string]$ext)      { throw [System.NotImplementedException]::new('SaveSnipContent') }
    [void]      DeleteSnipContent([string]$name, [string]$ext)                      { throw [System.NotImplementedException]::new('DeleteSnipContent') }
    [string]    FindSnipFile([string]$name)                                          { throw [System.NotImplementedException]::new('FindSnipFile') }
    [hashtable] GetConfig()                                                          { throw [System.NotImplementedException]::new('GetConfig') }
    [void]      SaveConfig([hashtable]$cfg, [string]$scope)                         { throw [System.NotImplementedException]::new('SaveConfig') }
    [void]      InvalidateCache()                                                    { throw [System.NotImplementedException]::new('InvalidateCache') }
}
