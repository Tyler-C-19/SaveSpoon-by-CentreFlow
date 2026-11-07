const BASE_URL = 'https://places.googleapis.com/v1';
const SEARCH_CENTRE = { latitude: 1.559, longitude: 103.6385 };
const SEARCH_RADIUS_METRES = 50000;

class PlacesError extends Error {}

function headers(fieldMask) {
  const key = process.env.GOOGLE_PLACES_API_KEY;
  if (!key) throw new PlacesError('GOOGLE_PLACES_API_KEY is not set');
  return { 'Content-Type': 'application/json', 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': fieldMask };
}

async function readJson(response) {
  if (!response.ok) throw new PlacesError(`Places API returned ${response.status}`);
  return response.json();
}

async function suggest(input, sessionToken) {
  const response = await fetch(`${BASE_URL}/places:autocomplete`, {
    method: 'POST',
    headers: headers('suggestions.placePrediction.placeId,suggestions.placePrediction.text.text'),
    body: JSON.stringify({
      input,
      sessionToken,
      includedRegionCodes: ['my'],
      locationBias: { circle: { center: SEARCH_CENTRE, radius: SEARCH_RADIUS_METRES } },
    }),
  });
  const data = await readJson(response);
  return (data.suggestions ?? [])
    .map((item) => item.placePrediction)
    .filter(Boolean)
    .map((place) => ({ placeId: place.placeId, text: place.text.text }));
}

async function locate(placeId, sessionToken) {
  const query = sessionToken ? `?${new URLSearchParams({ sessionToken })}` : '';
  const response = await fetch(`${BASE_URL}/places/${encodeURIComponent(placeId)}${query}`, {
    headers: headers('location'),
  });
  const { location } = await readJson(response);
  if (!location) throw new PlacesError('Place has no location');
  return { lat: location.latitude, lng: location.longitude };
}

module.exports = { suggest, locate, PlacesError };
