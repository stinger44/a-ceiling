/**
 * calculator.js — Smart Room Parameter Calculator
 * Alpha Ceiling | Frontend-only, localStorage DB
 */

// ─── NOMENCLATURE DATABASE ───────────────────────────────────────────────────
const DB_KEY = 'alpha_ceiling_nomenclature_v3';

const DEFAULT_ITEMS = [
  // Wall Materials (type: 'wall_material')
  { id: 1, name: 'Ткань Штукатурка', unit: 'м²', price: 2100, type: 'wall_material' },
  { id: 2, name: 'Ткань Узор', unit: 'м²', price: 2100, type: 'wall_material' },
  { id: 3, name: 'Ткань ТС Комфорт Г1', unit: 'м²', price: 2900, type: 'wall_material' },
  { id: 4, name: 'Ткань Комфорт', unit: 'м²', price: 1750, type: 'wall_material' },
  { id: 5, name: 'Ткань Орион', unit: 'м²', price: 1800, type: 'wall_material' },
  { id: 6, name: 'Ткань Комета', unit: 'м²', price: 1800, type: 'wall_material' },
  { id: 7, name: 'Ткань Акустик', unit: 'м²', price: 2100, type: 'wall_material' },
  { id: 8, name: 'Ткань Silencio', unit: 'м²', price: 2500, type: 'wall_material' },
  { id: 9, name: 'Ткань FORM Марс', unit: 'м²', price: 1900, type: 'wall_material' },
  { id: 10, name: 'Ткань FORM Луна', unit: 'м²', price: 1900, type: 'wall_material' },
  { id: 11, name: 'Ткань FORM', unit: 'м²', price: 1800, type: 'wall_material' },
  { id: 12, name: 'Архитектурный текстиль Celena', unit: 'м²', price: 2100, type: 'wall_material' },

  // Wall Profiles (type: 'wall_profile')
  { id: 101, name: 'Профиль ТС базовый', unit: 'м', price: 950, type: 'wall_profile' },
  { id: 102, name: 'Профиль ТС Стена-Потолок', unit: 'м', price: 1350, type: 'wall_profile' },
  { id: 103, name: 'Профиль ТС Окно-Откос', unit: 'м', price: 1800, type: 'wall_profile' },
  { id: 104, name: 'Профиль ТС Конструкционный', unit: 'м', price: 1550, type: 'wall_profile' },
  { id: 105, name: 'Профиль ТС КОНСТРУКТОР 5 см', unit: 'м', price: 1550, type: 'wall_profile' },
  { id: 106, name: 'Профиль ТС КАСКАД', unit: 'м', price: 2200, type: 'wall_profile' },
  { id: 107, name: 'Профиль ТС Внутренний угол', unit: 'м', price: 2150, type: 'wall_profile' },
  { id: 108, name: 'Профиль ТС Бокс (Стена-Потолок)', unit: 'м', price: 1400, type: 'wall_profile' },
  { id: 109, name: 'Световая Линия ТС 16мм', unit: 'м', price: 2500, type: 'wall_profile' },
  { id: 110, name: 'Разделитель ТС 2 мм', unit: 'м', price: 2300, type: 'wall_profile' },
  { id: 111, name: 'Плинтус ТС КОНТУР ПЛЮС (с подсветкой)', unit: 'м', price: 2400, type: 'wall_profile' },
  { id: 112, name: 'Плинтус теневой Мини ТС 15 мм', unit: 'м', price: 1300, type: 'wall_profile' },
  { id: 113, name: 'Отбойник ТС', unit: 'м', price: 1150, type: 'wall_profile' },

  // Ceiling Materials (type: 'ceil_material')
  { id: 201, name: 'Матовое полотно MSD Premium', unit: 'м²', price: 450, type: 'ceil_material' },
  { id: 202, name: 'Сатиновое полотно MSD Premium', unit: 'м²', price: 450, type: 'ceil_material' },
  { id: 203, name: 'Ткань Descor Premium (Германия)', unit: 'м²', price: 1200, type: 'ceil_material' },

  // Ceiling Profiles (type: 'ceil_profile')
  { id: 301, name: 'Классический ПВХ профиль', unit: 'м', price: 200, type: 'ceil_profile' },
  { id: 302, name: 'Алюминиевый профиль', unit: 'м', price: 350, type: 'ceil_profile' },
  { id: 303, name: 'Теневой профиль EuroKRAAB', unit: 'м', price: 900, type: 'ceil_profile' },
  { id: 304, name: 'Парящий профиль с подсветкой', unit: 'м', price: 1200, type: 'ceil_profile' },

  // Additional items
  { id: 401, name: 'Обход розетки/выключателя', unit: 'шт', price: 1050, type: 'other' },
  { id: 402, name: 'Обход трубы отопления', unit: 'шт', price: 300, type: 'other' },
  { id: 403, name: 'Установка светильника/люстры', unit: 'шт', price: 500, type: 'other' },
  { id: 404, name: 'Дополнительный угол (>4)', unit: 'шт', price: 300, type: 'other' },
  { id: 405, name: 'Обработка угла (стены)', unit: 'шт', price: 800, type: 'other' },

  // Base Works
  { id: 501, name: 'Натяжка текстиля для стен', unit: 'м²', price: 680, type: 'work' },
  { id: 502, name: 'Монтажные работы (потолок)', unit: 'м²', price: 300, type: 'work' }
];

function loadDB() {
  try {
    const raw = localStorage.getItem(DB_KEY);
    let items = raw ? JSON.parse(raw) : [...DEFAULT_ITEMS];
    // Ensure item 405 is present (fallback for existing localStorage users)
    if (!items.find(i => i.id === 405)) {
      items.push({ id: 405, name: 'Обработка угла (стены)', unit: 'шт', price: 800, type: 'other' });
      saveDB(items);
    }
    return items;
  } catch {
    return [...DEFAULT_ITEMS];
  }
}

function saveDB(items) {
  localStorage.setItem(DB_KEY, JSON.stringify(items));
}

// ─── STATE MANAGEMENT ────────────────────────────────────────────────────────
const state = {
  activeTab: 'walls', // 'walls' | 'ceilings'
  
  walls: {
    rooms: 1,
    corners: 4,
    length: 15,
    height: 2.8,
    doors: 1,
    windows: 2,
    sockets: 6,
    materialId: 1,
    profileId: 101
  },
  
  ceilings: {
    rooms: 1,
    area: 20,
    perimeter: 18,
    autoPerimeter: true,
    corners: 4,
    lights: 6,
    pipes: 0,
    materialId: 201,
    profileId: 301
  },
  
  db: loadDB()
};

document.addEventListener('DOMContentLoaded', () => {
  populateSelectors();
  initCustomSelect();
  syncInputsWithState();
  updateCalculation();
});

function populateSelectors() {
  const wallMatSelect = document.getElementById('wallMaterial');
  const wallMatOptions = document.getElementById('wallMaterialOptions');
  const wallProfSelect = document.getElementById('wallProfile');
  const ceilMatSelect = document.getElementById('ceilMaterial');
  const ceilProfSelect = document.getElementById('ceilProfile');

  // Clear options
  if (wallMatSelect) wallMatSelect.innerHTML = '';
  if (wallMatOptions) wallMatOptions.innerHTML = '';
  if (wallProfSelect) wallProfSelect.innerHTML = '';
  if (ceilMatSelect) ceilMatSelect.innerHTML = '';
  if (ceilProfSelect) ceilProfSelect.innerHTML = '';

  state.db.forEach(item => {
    if (item.type === 'wall_material') {
      if (wallMatSelect) {
        const option = `<option value="${item.id}">${item.name} (${item.price} ₽/${item.unit})</option>`;
        wallMatSelect.insertAdjacentHTML('beforeend', option);
      }

      // Custom option with thumbnail and data properties for hover preview
      if (wallMatOptions) {
        const thumbUrl = `images/thumb_fabric_wall_${item.id}.jpg?v=7`;
        const optionHtml = `
          <div class="custom-option" data-id="${item.id}" data-image="images/fabric_wall_${item.id}.jpg?v=7" data-name="${escHtml(item.name)}">
            <img class="custom-option-thumb" src="${thumbUrl}" alt="${escHtml(item.name)}">
            <div class="custom-option-info">
              <span class="custom-option-name">${escHtml(item.name)}</span>
              <span class="custom-option-price">${item.price} ₽/${item.unit}</span>
            </div>
          </div>
        `;
        wallMatOptions.insertAdjacentHTML('beforeend', optionHtml);
      }
    } else if (item.type === 'wall_profile') {
      if (wallProfSelect) {
        const option = `<option value="${item.id}">${item.name} (${item.price} ₽/${item.unit})</option>`;
        wallProfSelect.insertAdjacentHTML('beforeend', option);
      }
    } else if (item.type === 'ceil_material') {
      if (ceilMatSelect) {
        const option = `<option value="${item.id}">${item.name} (${item.price} ₽/${item.unit})</option>`;
        ceilMatSelect.insertAdjacentHTML('beforeend', option);
      }
    } else if (item.type === 'ceil_profile') {
      if (ceilProfSelect) {
        const option = `<option value="${item.id}">${item.name} (${item.price} ₽/${item.unit})</option>`;
        ceilProfSelect.insertAdjacentHTML('beforeend', option);
      }
    }
  });

  // Select values matching state
  if (wallMatSelect) wallMatSelect.value = state.walls.materialId;
  updateCustomSelectTrigger(state.walls.materialId);
  if (wallProfSelect) wallProfSelect.value = state.walls.profileId;
  if (ceilMatSelect) ceilMatSelect.value = state.ceilings.materialId;
  if (ceilProfSelect) ceilProfSelect.value = state.ceilings.profileId;
}

function updateCustomSelectTrigger(selectedId) {
  const item = state.db.find(i => i.id === selectedId);
  const triggerText = document.getElementById('wallMaterialTriggerText');
  const triggerIcon = document.getElementById('wallMaterialTriggerIcon');

  if (item && triggerText && triggerIcon) {
    triggerText.textContent = `${item.name} (${item.price} ₽/${item.unit})`;
    triggerIcon.src = `images/thumb_fabric_wall_${item.id}.jpg?v=7`;
    triggerIcon.style.display = 'block';
  }

  // Highlight active option in list
  const options = document.querySelectorAll('#wallMaterialOptions .custom-option');
  options.forEach(opt => {
    const id = parseInt(opt.getAttribute('data-id'));
    opt.classList.toggle('selected', id === selectedId);
  });
}

function initCustomSelect() {
  const wrapper = document.getElementById('wallMaterialWrapper');
  const trigger = document.getElementById('wallMaterialTrigger');
  const optionsContainer = document.getElementById('wallMaterialOptions');
  const hiddenSelect = document.getElementById('wallMaterial');
  const popup = document.getElementById('texturePreviewPopup');
  const popupImg = document.getElementById('texturePreviewImage');
  const popupName = document.getElementById('texturePreviewName');

  if (!wrapper || !trigger || !optionsContainer || !hiddenSelect || !popup) return;

  // Open/close dropdown
  trigger.addEventListener('click', (e) => {
    e.stopPropagation();
    wrapper.classList.toggle('open');
  });

  // Close when clicking outside
  document.addEventListener('click', (e) => {
    if (!wrapper.contains(e.target)) {
      wrapper.classList.remove('open');
    }
  });

  // Handle select click
  optionsContainer.addEventListener('click', (e) => {
    const option = e.target.closest('.custom-option');
    if (!option) return;

    const id = parseInt(option.getAttribute('data-id'));
    hiddenSelect.value = id;
    state.walls.materialId = id;

    updateCustomSelectTrigger(id);
    wrapper.classList.remove('open');
    popup.classList.remove('show');

    updateCalculation();
  });

  // Handle hover preview
  optionsContainer.addEventListener('mouseover', (e) => {
    const option = e.target.closest('.custom-option');
    if (!option) return;

    const imgUrl = option.getAttribute('data-image');
    const name = option.getAttribute('data-name');

    if (popupImg && popupName) {
      popupImg.src = imgUrl;
      popupName.textContent = name;
    }

    const rect = option.getBoundingClientRect();
    const wrapperRect = wrapper.getBoundingClientRect();

    // Position popup vertically matching the option
    popup.style.top = `${rect.top - wrapperRect.top}px`;

    // Position horizontally based on screen space
    if (wrapperRect.right + 230 > window.innerWidth) {
      popup.style.left = `-225px`;
    } else {
      popup.style.left = `${wrapperRect.width + 15}px`;
    }

    popup.classList.add('show');
  });

  optionsContainer.addEventListener('mouseout', (e) => {
    const option = e.target.closest('.custom-option');
    if (option) {
      popup.classList.remove('show');
    }
  });
}

function syncInputsWithState() {
  // Walls inputs
  const wlInput = document.getElementById('wallLength');
  const whInput = document.getElementById('wallHeight');
  if (wlInput) wlInput.value = state.walls.length;
  if (whInput) whInput.value = state.walls.height;
  
  updateDisplayLabel('valWallLength', `${state.walls.length} м`);
  updateDisplayLabel('valWallHeight', `${state.walls.height} м`);
  updateDisplayLabel('wallsRooms', state.walls.rooms);
  updateDisplayLabel('wallsCorners', state.walls.corners);
  updateDisplayLabel('wallsDoors', state.walls.doors);
  updateDisplayLabel('wallsWindows', state.walls.windows);
  updateDisplayLabel('wallsSockets', state.walls.sockets);

  // Ceilings inputs
  const caInput = document.getElementById('ceilArea');
  const cpInput = document.getElementById('ceilPerimeter');
  const cpAuto = document.getElementById('ceilAutoPerimeter');
  if (caInput) caInput.value = state.ceilings.area;
  if (cpInput) cpInput.value = state.ceilings.perimeter;
  if (cpAuto) cpAuto.checked = state.ceilings.autoPerimeter;

  if (cpInput) cpInput.disabled = state.ceilings.autoPerimeter;

  updateDisplayLabel('valCeilArea', `${state.ceilings.area} м²`);
  updateDisplayLabel('valCeilPerimeter', `${state.ceilings.perimeter} м`);
  updateDisplayLabel('ceilRooms', state.ceilings.rooms);
  updateDisplayLabel('ceilCorners', state.ceilings.corners);
  updateDisplayLabel('ceilLights', state.ceilings.lights);
  updateDisplayLabel('ceilPipes', state.ceilings.pipes);
}

function updateDisplayLabel(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = value;
}

// ─── TAB SWITCHING ───────────────────────────────────────────────────────────
window.switchTab = function(tabName) {
  state.activeTab = tabName;
  
  // Toggle buttons
  const wallsBtn = document.getElementById('btnTabWalls');
  const ceilingsBtn = document.getElementById('btnTabCeilings');
  if (wallsBtn && ceilingsBtn) {
    wallsBtn.classList.toggle('active', tabName === 'walls');
    ceilingsBtn.classList.toggle('active', tabName === 'ceilings');
  }

  // Toggle content blocks
  const wallsContent = document.getElementById('tabContentWalls');
  const ceilingsContent = document.getElementById('tabContentCeilings');
  if (wallsContent && ceilingsContent) {
    wallsContent.classList.toggle('active', tabName === 'walls');
    ceilingsContent.classList.toggle('active', tabName === 'ceilings');
  }

  updateCalculation();
};

// ─── SLIDERS AND COUNTERS CONTROL ────────────────────────────────────────────
window.adjustCounter = function(fieldId, change) {
  let target;
  let key;
  const isWalls = fieldId.startsWith('walls');
  
  if (isWalls) {
    target = state.walls;
    key = fieldId.replace('walls', '').toLowerCase(); // 'rooms', 'corners', 'doors', 'windows', 'sockets'
  } else {
    target = state.ceilings;
    key = fieldId.replace('ceil', '').toLowerCase(); // 'rooms', 'corners', 'lights', 'pipes'
  }

  let minVal = 0;
  if (key === 'rooms') {
    minVal = 1;
  } else if (key === 'corners') {
    minVal = 4 * target.rooms; // Min 4 corners per room
  }

  if (key === 'rooms') {
    const oldRooms = target.rooms;
    target.rooms = Math.max(minVal, target.rooms + change);
    const actualChange = target.rooms - oldRooms;
    
    // Automatically adjust corners by ±4 based on actual rooms change
    target.corners = Math.max(4 * target.rooms, target.corners + (actualChange * 4));
    
    // Sync UI display for corners
    const cornersFieldId = isWalls ? 'wallsCorners' : 'ceilCorners';
    updateDisplayLabel(cornersFieldId, target.corners);
  } else {
    target[key] = Math.max(minVal, target[key] + change);
  }

  updateDisplayLabel(fieldId, target[key]);
  updateCalculation();
};

window.onCeilAreaInput = function() {
  const areaInput = document.getElementById('ceilArea');
  if (!areaInput) return;
  state.ceilings.area = parseInt(areaInput.value) || 5;
  updateDisplayLabel('valCeilArea', `${state.ceilings.area} м²`);

  if (state.ceilings.autoPerimeter) {
    // Standard square root perimeter approximation: 4 * sqrt(area), rounded up
    state.ceilings.perimeter = Math.ceil(4 * Math.sqrt(state.ceilings.area));
    const cpInput = document.getElementById('ceilPerimeter');
    if (cpInput) cpInput.value = state.ceilings.perimeter;
    updateDisplayLabel('valCeilPerimeter', `${state.ceilings.perimeter} м`);
  }

  updateCalculation();
};

window.onCeilPerimeterInput = function() {
  const perimInput = document.getElementById('ceilPerimeter');
  if (!perimInput) return;
  state.ceilings.perimeter = parseInt(perimInput.value) || 6;
  updateDisplayLabel('valCeilPerimeter', `${state.ceilings.perimeter} м`);
  updateCalculation();
};

window.onAutoPerimeterToggle = function() {
  const cpAuto = document.getElementById('ceilAutoPerimeter');
  const cpInput = document.getElementById('ceilPerimeter');
  if (!cpAuto || !cpInput) return;

  state.ceilings.autoPerimeter = cpAuto.checked;
  cpInput.disabled = state.ceilings.autoPerimeter;

  if (state.ceilings.autoPerimeter) {
    state.ceilings.perimeter = Math.ceil(4 * Math.sqrt(state.ceilings.area));
    cpInput.value = state.ceilings.perimeter;
    updateDisplayLabel('valCeilPerimeter', `${state.ceilings.perimeter} м`);
  }
  updateCalculation();
};

// ─── CALCULATIONS ENGINE ─────────────────────────────────────────────────────
window.updateCalculation = function() {
  // Sync select controls with state
  const wallMatSelect = document.getElementById('wallMaterial');
  const wallProfSelect = document.getElementById('wallProfile');
  const ceilMatSelect = document.getElementById('ceilMaterial');
  const ceilProfSelect = document.getElementById('ceilProfile');

  if (wallMatSelect) state.walls.materialId = parseInt(wallMatSelect.value);
  if (wallProfSelect) state.walls.profileId = parseInt(wallProfSelect.value);
  if (ceilMatSelect) state.ceilings.materialId = parseInt(ceilMatSelect.value);
  if (ceilProfSelect) state.ceilings.profileId = parseInt(ceilProfSelect.value);

  // Sync sliders
  const wlInput = document.getElementById('wallLength');
  const whInput = document.getElementById('wallHeight');
  if (wlInput) {
    state.walls.length = parseInt(wlInput.value);
    updateDisplayLabel('valWallLength', `${state.walls.length} м`);
  }
  if (whInput) {
    state.walls.height = parseFloat(whInput.value);
    updateDisplayLabel('valWallHeight', `${state.walls.height} м`);
  }

  let finalArea = 0;
  let finalPerim = 0;
  let materialCost = 0;
  let profileCost = 0;
  let workCost = 0;
  let totalCost = 0;

  if (state.activeTab === 'walls') {
    // 🔊 WALLS MODE
    
    // 1. Calculate billed fabric length and roll width
    let rollWidth = 3.2;
    let billedFabricArea = 0;
    let fabricLength = 0;
    let separatorLength = 0;

    if (state.walls.height <= 2.7) {
      rollWidth = 2.9;
      fabricLength = state.walls.length + (0.2 * state.walls.rooms);
      billedFabricArea = fabricLength * rollWidth;
    } else if (state.walls.height <= 3.0) {
      rollWidth = 3.2;
      fabricLength = state.walls.length + (0.2 * state.walls.rooms);
      billedFabricArea = fabricLength * rollWidth;
    } else {
      rollWidth = 3.2;
      const strips = Math.ceil(state.walls.length / 3.0);
      fabricLength = strips * (state.walls.height + 0.2);
      billedFabricArea = fabricLength * 3.2;
      separatorLength = (strips - 1) * state.walls.height;
    }
    
    finalArea = billedFabricArea; // For display and material cost mapping
    
    // Clean work area (for actual installation work pricing)
    const rawWorkArea = (state.walls.length * state.walls.height) - (state.walls.doors * 1.8) - (state.walls.windows * 2.1);
    const cleanWorkArea = Math.max(1.0, parseFloat(rawWorkArea.toFixed(2)));
    
    // Total physical length of profile bounds (perimeter style summary in Smeta)
    // Here we show top + bottom length as final perimeter for summary display
    finalPerim = 2 * state.walls.length;

    // Get pricing components
    const materialItem = state.db.find(i => i.id === state.walls.materialId);
    const baseProfile = state.db.find(i => i.id === 101); // ID 101 - Профиль ТС базовый
    const boxProfile = state.db.find(i => i.id === 108);  // ID 108 - Профиль ТС Бокс (Стена-Потолок)
    const plinthMiniProfile = state.db.find(i => i.id === 112); // ID 112 - Плинтус теневой Мини ТС 15 мм
    const separatorProfile = state.db.find(i => i.id === 110); // ID 110 - Разделитель ТС 2 мм
    const workItem = state.db.find(i => i.type === 'work' && i.name.includes('стен')); // ID 501
    const socketItem = state.db.find(i => i.id === 401); // Обход розетки
    const cornerProcessingItem = state.db.find(i => i.id === 405); // Обработка угла (стены)

    const pBase = baseProfile ? baseProfile.price : 950;
    const pBox = boxProfile ? boxProfile.price : 1400;
    const pPlinthMini = plinthMiniProfile ? plinthMiniProfile.price : 1300;
    const pSeparator = separatorProfile ? separatorProfile.price : 2300;

    // Top Profile is always Box (108) by default
    const pTop = pBox;
    // Bottom Profile is always Plinth Mini (112) by default
    const pBottom = pPlinthMini;

    // Material Cost (billed fabric area * fabric price)
    if (materialItem) materialCost = billedFabricArea * materialItem.price;

    // Profile Cost (materials part):
    // Top profile + Bottom profile + Vertical corners + Separators + Doors profiles + Windows profiles
    const topProfileCost = state.walls.length * pTop;
    const bottomProfileCost = state.walls.length * pBottom;
    const cornersProfileCost = state.walls.corners * state.walls.height * pBase;
    const separatorProfileCost = separatorLength * pSeparator;
    const doorsProfileCost = state.walls.doors * 4.9 * pBase;
    const windowsProfileCost = state.walls.windows * 5.8 * pBase;

    profileCost = topProfileCost + bottomProfileCost + cornersProfileCost + separatorProfileCost + doorsProfileCost + windowsProfileCost;
    
    // Work Cost:
    // Base installation work (cleanWorkArea * 680)
    // + Sockets bypass work (sockets * 1050)
    // + Corner processing work (corners * 800)
    // + Door bypass work (doors * 3000)
    // + Window bypass work (windows * 2800)
    const baseWorkPrice = workItem ? workItem.price : 680;
    const socketPrice = socketItem ? socketItem.price : 1050;
    const cornerProcessingPrice = cornerProcessingItem ? cornerProcessingItem.price : 800;

    workCost = (cleanWorkArea * baseWorkPrice) +
               (state.walls.sockets * socketPrice) +
               (state.walls.corners * cornerProcessingPrice) +
               (state.walls.doors * 3000) +
               (state.walls.windows * 2800);
    
    totalCost = materialCost + profileCost + workCost;

    // Sync specific Smeta elements to display clean work area for information
    updateDisplayLabel('smetaArea', `${cleanWorkArea.toFixed(2)} м² (расход ткани: ${billedFabricArea.toFixed(2)} м²)`);
    updateDisplayLabel('smetaPerimeter', `${finalPerim} м (углы: ${state.walls.corners} шт)`);

  } else {
    // ☁️ CEILINGS MODE
    finalArea = state.ceilings.area;
    finalPerim = state.ceilings.perimeter;

    // Get pricing components
    const materialItem = state.db.find(i => i.id === state.ceilings.materialId);
    const profileItem = state.db.find(i => i.id === state.ceilings.profileId);
    const workItem = state.db.find(i => i.type === 'work' && i.name.includes('потолок')); // ID 502
    
    // Additional elements
    const lightItem = state.db.find(i => i.id === 403); // Светильник
    const pipeItem = state.db.find(i => i.id === 402);  // Труба
    const cornerItem = state.db.find(i => i.id === 404); // Доп угол

    if (materialItem) materialCost = finalArea * materialItem.price;
    if (profileItem) profileCost = finalPerim * profileItem.price;

    const baseWorkPrice = workItem ? workItem.price : 300;
    const lightPrice = lightItem ? lightItem.price : 500;
    const pipePrice = pipeItem ? pipeItem.price : 300;
    const cornerPrice = cornerItem ? cornerItem.price : 300;

    // Extra corners beyond 4 * rooms are charged extra
    const extraCorners = Math.max(0, state.ceilings.corners - (4 * state.ceilings.rooms));

    workCost = (finalArea * baseWorkPrice) + 
               (state.ceilings.lights * lightPrice) + 
               (state.ceilings.pipes * pipePrice) + 
               (extraCorners * cornerPrice);

    totalCost = materialCost + profileCost + workCost;

    updateDisplayLabel('smetaArea', `${finalArea.toFixed(2)} м²`);
    updateDisplayLabel('smetaPerimeter', `${finalPerim} м (углы: ${state.ceilings.corners} шт)`);
  }

  // Update DOM Smeta Price Labels
  updateDisplayLabel('smetaMaterialPrice', formatRub(materialCost));
  updateDisplayLabel('smetaProfilePrice', formatRub(profileCost));
  updateDisplayLabel('smetaWorkPrice', formatRub(workCost));
  updateDisplayLabel('totalSum', formatRub(totalCost));

  // Sync lead summary report text
  syncLeadReport(finalArea, finalPerim, materialCost, profileCost, workCost, totalCost);
};

function formatRub(num) {
  return num.toLocaleString('ru-RU', { minimumFractionDigits: 0, maximumFractionDigits: 0 }) + ' ₽';
}

// ─── REPORT SUMMARY GENERATOR ────────────────────────────────────────────────
function syncLeadReport(area, perim, matCost, profCost, workCost, total) {
  const summaryEl = document.getElementById('leadSummary');
  if (!summaryEl) return;

  const lines = [];
  if (state.activeTab === 'walls') {
    const mat = state.db.find(i => i.id === state.walls.materialId)?.name || '';
    const prof = state.db.find(i => i.id === state.walls.profileId)?.name || '';
    
    let rollWidth = 3.2;
    let fabricLength = 0;
    let reportStripsInfo = "";
    
    if (state.walls.height <= 2.7) {
      rollWidth = 2.9;
      fabricLength = state.walls.length + (0.2 * state.walls.rooms);
    } else if (state.walls.height <= 3.0) {
      rollWidth = 3.2;
      fabricLength = state.walls.length + (0.2 * state.walls.rooms);
    } else {
      rollWidth = 3.2;
      const strips = Math.ceil(state.walls.length / 3.0);
      fabricLength = strips * (state.walls.height + 0.2);
      reportStripsInfo = ` (вертикальные полосы: ${strips} шт по ${(state.walls.height + 0.2).toFixed(1)} м)`;
    }
    
    const cleanWorkArea = Math.max(1.0, (state.walls.length * state.walls.height) - (state.walls.doors * 1.8) - (state.walls.windows * 2.1));

    lines.push(`ТИП РАСЧЕТА: Акустические тканевые стены`);
    lines.push(`Количество комнат (помещений): ${state.walls.rooms}`);
    lines.push(`Длина стен: ${state.walls.length} м, Высота: ${state.walls.height} м, Углов: ${state.walls.corners} шт`);
    lines.push(`Дверей (обход): ${state.walls.doors} шт, Окна (обход): ${state.walls.windows} шт, Розетки: ${state.walls.sockets} шт`);
    lines.push(`Ткань: ${mat}`);
    lines.push(`Багет: ТС Бокс (верх) + Теневой плинтус Мини (низ)`);
    lines.push(`Расход ткани (погонный метр от рулона): ${fabricLength.toFixed(1)} м при ширине рулона ${rollWidth.toFixed(1)} м${reportStripsInfo}`);
    lines.push(`Фактическая площадь работы: ${cleanWorkArea.toFixed(2)} м²`);
  } else {
    const mat = state.db.find(i => i.id === state.ceilings.materialId)?.name || '';
    const prof = state.db.find(i => i.id === state.ceilings.profileId)?.name || '';
    lines.push(`ТИП РАСЧЕТА: Натяжные потолки`);
    lines.push(`Количество комнат (помещений): ${state.ceilings.rooms}`);
    lines.push(`Площадь: ${state.ceilings.area} м², Периметр: ${state.ceilings.perimeter} м`);
    lines.push(`Углы: ${state.ceilings.corners} шт (доп. углов: ${Math.max(0, state.ceilings.corners - 4 * state.ceilings.rooms)} шт)`);
    lines.push(`Светильники: ${state.ceilings.lights} шт, Трубы: ${state.ceilings.pipes} шт`);
    lines.push(`Полотно: ${mat}`);
    lines.push(`Профиль: ${prof}`);
  }

  lines.push(`--- СМЕТА ---`);
  if (state.activeTab === 'walls') {
    lines.push(`Площадь работы: ${Math.max(1.0, (state.walls.length * state.walls.height) - (state.walls.doors * 1.8) - (state.walls.windows * 2.1)).toFixed(2)} м²`);
    lines.push(`Площадь ткани: ${area.toFixed(2)} м²`);
  } else {
    lines.push(`Площадь отделки: ${area.toFixed(2)} м²`);
  }
  lines.push(`Длина профилей: ${perim} м`);
  lines.push(`Стоимость материала: ${formatRub(matCost)}`);
  lines.push(`Стоимость профилей: ${formatRub(profCost)}`);
  lines.push(`Работы и допы: ${formatRub(workCost)}`);
  lines.push(`ИТОГО: ${formatRub(total)}`);

  summaryEl.value = lines.join('\n');
}

// ─── LEAD FORM SUBMISSION ────────────────────────────────────────────────────
window.submitLead = function(e) {
  e.preventDefault();
  
  const name = document.getElementById('leadName')?.value || '';
  const phone = document.getElementById('leadPhone')?.value || '';
  const summary = document.getElementById('leadSummary')?.value || '';

  console.log('--- ОТПРАВЛЕНА ЗАЯВКА НА ЗАМЕР ---');
  console.log(`Имя: ${name}`);
  console.log(`Телефон: ${phone}`);
  console.log(`Сводный расчет:\n${summary}`);
  
  const formEl = document.getElementById('leadForm');
  const successEl = document.getElementById('leadSuccess');
  if (formEl) formEl.style.display = 'none';
  if (successEl) successEl.classList.add('show');
};

function escHtml(str) {
  return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
