// Mobile Menu
const mobileMenuBtn = document.getElementById('mobileMenuBtn');
const mobileNav = document.getElementById('mobileNav');
const mobileLinks = document.querySelectorAll('.mobile-nav-list a');

mobileMenuBtn.addEventListener('click', () => {
    mobileMenuBtn.classList.toggle('active');
    mobileNav.classList.toggle('active');
    document.body.style.overflow = mobileNav.classList.contains('active') ? 'hidden' : '';
});

mobileLinks.forEach(link => {
    link.addEventListener('click', () => {
        mobileMenuBtn.classList.remove('active');
        mobileNav.classList.remove('active');
        document.body.style.overflow = '';
    });
});

// Modal Logic
const modal = document.getElementById('leadModal');

function openModal(service = '') {
    modal.classList.add('active');
    document.body.style.overflow = 'hidden';
    
    // If a specific service was clicked, we could update the form or log it
    if (service) {
        console.log(`User interested in: ${service}`);
        // Optionally update hidden input in form
    }
}

function closeModal() {
    modal.classList.remove('active');
    document.body.style.overflow = '';
}

// Close modal on click outside
modal.addEventListener('click', (e) => {
    if (e.target === modal) {
        closeModal();
    }
});

// Reviews Slider Logic
const track = document.getElementById('reviewsTrack');
const prevBtn = document.getElementById('prevBtn');
const nextBtn = document.getElementById('nextBtn');
const cards = Array.from(track.children);

// Initially wrap cards to apply wrapper styling directly via JS if needed
cards.forEach(card => {
    // Actually we handled layout via CSS flex (width 33.333% for desktop etc)
    // But for simplicity of responsive slider, let's inject a wrapper approach or calculate translate
});

let currentIndex = 0;
const totalCards = cards.length;

function getCardsPerView() {
    if (window.innerWidth >= 1024) return 3;
    if (window.innerWidth >= 768) return 2;
    return 1;
}

function updateSlider() {
    const cardsPerView = getCardsPerView();
    // Re-adjust sizing based on cards per view
    const cardWidth = 100 / cardsPerView;
    
    // Set track width dynamically
    track.style.width = `${(totalCards / cardsPerView) * 100}%`;
    
    cards.forEach(card => {
        card.style.width = `${100 / totalCards}%`;
    });

    const maxIndex = totalCards - cardsPerView;
    if (currentIndex > maxIndex) {
        currentIndex = maxIndex;
    }
    
    // Percentage translation based on original track width vs container
    // A simpler approach: translateX by (currentIndex * -100 / cardsPerView)%
    const translateValue = (currentIndex * -100) / totalCards;
    track.style.transform = `translateX(${translateValue}%)`;
}

// Initialize slider structure on load and resize
window.addEventListener('resize', updateSlider);
updateSlider();

prevBtn.addEventListener('click', () => {
    if (currentIndex > 0) {
        currentIndex--;
        updateSlider();
    }
});

nextBtn.addEventListener('click', () => {
    const cardsPerView = getCardsPerView();
    const maxIndex = totalCards - cardsPerView;
    if (currentIndex < maxIndex) {
        currentIndex++;
        updateSlider();
    }
});

// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const targetId = this.getAttribute('href');
        if (targetId === '#') return;
        
        const targetElement = document.querySelector(targetId);
        if (targetElement) {
            targetElement.scrollIntoView({
                behavior: 'smooth'
            });
        }
    });
});
