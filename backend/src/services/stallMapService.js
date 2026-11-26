// The most items per stall sent with the map, as many as the stall pane shows.
const MATCHES_PER_STALL = 4;

// Groups listings on sale into one map marker per stall. Vendor IDs stay on the server.
// Each stall keeps its first few listings, so the pane can show what matched first.
function groupByStall(listings) {
  const stalls = new Map();
  for (const { _stall, ...listing } of listings) {
    const key = String(_stall);
    if (!Array.isArray(listing.location) || listing.location.length !== 2) continue;
    const stall = stalls.get(key);
    if (stall) {
      stall.count += 1;
      if (stall.matches.length < MATCHES_PER_STALL) stall.matches.push(listing);
    } else {
      stalls.set(key, {
        stallName: listing.stallName,
        address: listing.pickupAddress,
        location: listing.location,
        count: 1,
        listing,
        matches: [listing],
      });
    }
  }
  return [...stalls.values()].sort((a, b) => a.stallName.localeCompare(b.stallName));
}

module.exports = { groupByStall, MATCHES_PER_STALL };
