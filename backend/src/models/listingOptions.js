const CATEGORIES = ['Rice', 'Noodles', 'Desserts', 'Snacks', 'Drinks', 'Other'];

const ALLERGENS = [
  'egg',
  'milk',
  'gluten',
  'soy',
  'peanut',
  'fish',
  'shellfish',
  'sesame',
  'coconut',
  'belacan',
];

const OTHER_ALLERGEN_PATTERN = /^\p{L}[\p{L} '-]{1,39}$/u;
const MAX_OTHER_ALLERGENS = 5;

function titleCase(value) {
  return value
    .trim()
    .replace(/ +/g, ' ')
    .toLowerCase()
    .replace(/(^|[ -])\p{L}/gu, (start) => start.toUpperCase());
}

function normaliseAllergens(allergens = [], otherAllergens = []) {
  const listed = new Set(allergens);
  const other = new Map();
  for (const item of otherAllergens) {
    const name = titleCase(item);
    const key = name.toLowerCase();
    if (ALLERGENS.includes(key)) listed.add(key);
    else if (!other.has(key)) other.set(key, name);
  }
  return { allergens: [...listed], otherAllergens: [...other.values()] };
}

module.exports = {
  CATEGORIES,
  ALLERGENS,
  OTHER_ALLERGEN_PATTERN,
  MAX_OTHER_ALLERGENS,
  normaliseAllergens,
};
