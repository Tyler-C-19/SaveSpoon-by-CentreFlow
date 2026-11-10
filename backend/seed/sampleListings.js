const hoursFromNow = (h) => new Date(Date.now() + h * 60 * 60 * 1000);

function sampleListings([stall1, stall2, stall3]) {
  const make = (stall, fields) => ({ vendor: stall._id, location: stall.location, ...fields });

  return [
    make(stall1, {
      title: 'Nasi Campur Set', description: 'Rice with 2 dishes and a vegetable',
      category: 'Rice', isHalal: true,
      originalPrice: 8, discountedPrice: 4.5, quantityAvailable: 6,
      pickupStart: hoursFromNow(1), pickupEnd: hoursFromNow(3), allergens: ['egg'],
    }),
    make(stall1, {
      title: 'Ayam Goreng Rice', description: 'Fried chicken with rice and sambal',
      category: 'Rice', isHalal: true,
      originalPrice: 7, discountedPrice: 4, quantityAvailable: 4,
      pickupStart: hoursFromNow(1), pickupEnd: hoursFromNow(3), allergens: ['soy'],
    }),
    make(stall2, {
      title: 'Mee Goreng Mamak', description: 'Spicy fried noodles with egg',
      category: 'Noodles', isHalal: true,
      originalPrice: 6, discountedPrice: 3.5, quantityAvailable: 8,
      pickupStart: hoursFromNow(2), pickupEnd: hoursFromNow(4), allergens: ['gluten', 'egg', 'soy'],
    }),
    make(stall2, {
      title: 'Roti Canai (2 pcs) with Dhal', description: 'Fresh roti canai with dhal',
      category: 'Snacks', isHalal: true,
      originalPrice: 3.5, discountedPrice: 2, quantityAvailable: 10,
      pickupStart: hoursFromNow(2), pickupEnd: hoursFromNow(4), allergens: ['gluten', 'milk'],
    }),
    make(stall3, {
      title: 'Chicken Sandwich', description: 'Grilled chicken, lettuce and mayo',
      category: 'Snacks', isHalal: false,
      originalPrice: 5, discountedPrice: 3, quantityAvailable: 5,
      pickupStart: hoursFromNow(1), pickupEnd: hoursFromNow(2), allergens: ['gluten', 'egg'],
    }),
    make(stall3, {
      title: 'Assorted Kuih Box', description: 'Box of 6 mixed kuih',
      category: 'Desserts', isHalal: true,
      originalPrice: 6, discountedPrice: 3.5, quantityAvailable: 0,
      pickupStart: hoursFromNow(1), pickupEnd: hoursFromNow(3), allergens: ['coconut', 'gluten'], status: 'sold_out',
    }),
  ];
}

module.exports = { sampleListings, STALL_NAMES: ['Warung Pak Din', 'Kafe Cendana', 'Roti Bakar Kak Ina'] };
