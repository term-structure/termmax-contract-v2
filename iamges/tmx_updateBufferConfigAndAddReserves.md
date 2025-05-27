```mermaid
sequenceDiagram
    title TermMaxToken - updateBufferConfigAndAddReserves()
    actor Owner
    participant TMT as TermMaxToken
    participant uTkn as IERC20 (underlying)

    Owner->>TMT: updateBufferConfigAndAddReserves(additionalReserves, newBufferConfig)
    activate TMT

    TMT->>uTkn: safeTransferFrom(Owner, TMT, additionalReserves)
    activate uTkn
    uTkn-->>TMT: // Return signal from safeTransferFrom
    deactivate uTkn

    TMT->>TMT: _updateBufferConfig(newBufferConfig)
    activate TMT #LightSkyBlue
        TMT->>TMT: _checkBufferConfig(newBufferConfig.minimumBuffer, newBufferConfig.maximumBuffer, newBufferConfig.buffer)
        TMT->>TMT: (updates storage: this.bufferConfig = newBufferConfig)
        TMT->>TMT: emit UpdateBufferConfig(newBufferConfig.minimumBuffer, newBufferConfig.maximumBuffer, newBufferConfig.buffer)
    deactivate TMT #LightSkyBlue

    TMT-->>Owner: (success)
    deactivate TMT
```