# Togagrid Flow Diagram

This diagram describes the flow and architecture of the `togagrid.lua` script, which creates a virtual grid controller that bridges between a physical grid device and OSC-based TouchOSC clients.

```mermaid
graph TD
    A[Script Start] --> B["togagrid:connect()"]
    B --> C["togagrid:init()"]
    
    C --> D[Initialize Buffers]
    C --> E[Hook OSC Input]
    C --> F[Hook Cleanup]
    C --> G[Start Background Sync]
    C --> H[Connect to Physical Grid]
    
    D --> D1[old_buffer: 16x8]
    D --> D2[new_buffer: 16x8]
    D --> D3[dirty flags: 16x8]
    
    E --> E1[Save original osc.event]
    E1 --> E2[Replace with togagrid.osc_in]
    
    F --> F1[Save original grid.cleanup]
    F1 --> F2[Replace with togagrid.cleanup]
    
    G --> G1[Start Clock Coroutine]
    G1 --> G2[Background Sync Loop]
    
    H --> H1[Connect to Physical Grid]
    H1 --> H2[Set Physical Grid Key Handler]
    
    subgraph "Main Event Loop"
        I[OSC Message Received]
        I --> J{Path Type?}
        
        J -->|"/toga_connection"| K[New Client Connection]
        J -->|"/togagrid/N"| L[Grid Button Press]
        J -->|Other| M[Pass to Original Handler]
        
        K --> K1[Add to Destination List]
        K1 --> K2[Send Full Grid State]
        K2 --> K3[Send Connection Confirmation]
        
        L --> L1[Parse Button Coordinates]
        L1 --> L2[Call Application Key Handler]
    end
    
    subgraph "LED Update System"
        N["Application Calls led(x,y,z)"]
        N --> O[Update new_buffer]
        O --> P[Set dirty flag]
        P --> Q[Also Update Physical Grid]
        
        R["Application Calls refresh()"]
        R --> S{Force Refresh?}
        S -->|Yes| T[Send All LEDs]
        S -->|No| U[Send Only Dirty LEDs]
        T --> V[Clear All Dirty Flags]
        U --> W[Clear Individual Dirty Flags]
        V --> X[Send OSC Messages]
        W --> X
    end
    
    subgraph "Background Sync Process"
        G2 --> Y{Cleanup Done?}
        Y -->|No| Z[Wait 250ms]
        Z --> AA{Has Destinations?}
        AA -->|Yes| BB[Sync One Batch Row]
        AA -->|No| Y
        BB --> CC[Update LEDs for Batch]
        CC --> DD[Move to Next Batch]
        DD --> Y
        Y -->|Yes| EE[Exit Sync Loop]
    end
    
    subgraph "Cleanup Process"
        FF[Script Shutdown] --> GG["togagrid.cleanup()"]
        GG --> HH[Cancel Background Sync]
        HH --> II[Clear All LEDs]
        II --> JJ[Send Disconnection Signal]
        JJ --> KK[Call Original Cleanup]
    end
    
    subgraph "TouchOSC Clients"
        LL[TouchOSC Client 1]
        MM[TouchOSC Client 2]
        NN[TouchOSC Client N...]
    end
    
    X --> LL
    X --> MM
    X --> NN
    
    LL -.->|OSC Messages| I
    MM -.->|OSC Messages| I
    NN -.->|OSC Messages| I
    
    style A fill:#e1f5fe
    style C fill:#f3e5f5
    style G2 fill:#fff3e0
    style GG fill:#ffebee
    style LL fill:#e8f5e8
    style MM fill:#e8f5e8
    style NN fill:#e8f5e8
```

## Key Components

### 1. **Initialization Phase**
- Sets up dual buffer system (old_buffer, new_buffer, dirty flags)
- Hooks into Norns' OSC input system
- Hooks into cleanup system
- Starts background synchronization process
- Connects to physical grid device

### 2. **Dual Buffer System**
- **new_buffer**: Current state that applications write to
- **old_buffer**: Previously sent state for change detection  
- **dirty flags**: Track which LEDs need updates

### 3. **OSC Communication**
- Listens for `/toga_connection` messages from new TouchOSC clients
- Processes `/togagrid/N` button press messages
- Sends LED updates as `/togagrid/N` with brightness values (0.0-1.0)
- Sends connection status via `/toga_connection`

### 4. **Background Sync**
- Runs every 250ms in a separate coroutine
- Syncs one batch of rows per cycle for efficient network usage
- Prevents overwhelming TouchOSC clients with updates

### 5. **Event Flow**
1. TouchOSC client sends button press → OSC handler → Application key callback
2. Application updates LEDs → Buffer updates → Dirty flag marking
3. Application calls refresh → Send dirty/all LEDs → Clear dirty flags
4. Background sync continuously sends batched updates

### 6. **Resource Management**
- Graceful cleanup on script shutdown
- Clears all LEDs before disconnecting
- Cancels background processes
- Restores original OSC/cleanup handlers