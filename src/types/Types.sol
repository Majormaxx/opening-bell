// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Session the hook has applied to the pool.
enum Session {
    CLOSED,
    OPEN
}

/// @notice Market status of a reference print. Numeric values follow the
/// marketStatus field of Chainlink's RWA v11 (24/5) report schema.
enum MarketStatus {
    UNKNOWN,
    PRE,
    REGULAR,
    POST,
    OVERNIGHT,
    CLOSED
}

/// @notice A reference price observation.
/// @param priceX18 Quote per base, 18-decimal fixed point, human units.
/// @param observedAt Time the price was observed at the source.
/// @param status Market status at the source when observed.
struct Print {
    uint256 priceX18;
    uint64 observedAt;
    MarketStatus status;
}

/// @notice Liquidity terms for one session.
/// @param rangeBps Half-width of the position around the strike, in ticks (1 tick is about 1 bp).
/// @param deployBps Share of idle vault inventory deployed into the pool, 0..10000.
/// @param feePips LP fee charged on swaps, in pips (3000 = 0.30%).
struct SessionParams {
    uint16 rangeBps;
    uint16 deployBps;
    uint24 feePips;
}

/// @notice The curator's parameter set.
struct Mandate {
    SessionParams open;
    SessionParams closed;
    uint32 haltLead; // seconds before the bell that continuous trading halts
    uint32 freezeLead; // seconds before the bell that on-open cancels freeze
    uint16 crossDepthBps; // share of open liquidity offered to absorb the book imbalance
    uint16 collarBps; // max distance of the clearing price from the reference, in ticks
    uint24 crossFeePips; // fee on crossed output, kept by the vault
    uint24 rampFeePips; // extra swap fee at the bell, decaying linearly to zero
    uint32 rampSecs; // duration of the post-bell fee ramp
}

/// @notice Immutable limits a mandate must sit inside, accepted by depositors up front.
struct Bounds {
    Mandate min;
    Mandate max;
    uint16 maxPerfFeeBps;
}
