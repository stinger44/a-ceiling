// Mobile Menu

const mobileMenuBtn = document.getElementById('mobileMenuBtn');

const mobileNav = document.getElementById('mobileNav');



if (mobileMenuBtn && mobileNav) {

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

}







// Reviews Slider Logic (Dynamic loading from reviews.json)
async function initReviewsSlider() {
    const track = document.getElementById('reviewsTrack');
    const prevBtn = document.getElementById('prevBtn');
    const nextBtn = document.getElementById('nextBtn');

    if (!track || !prevBtn || !nextBtn) return;

    try {
        const response = await fetch('data/reviews.json');
        if (response.ok) {
            const reviews = await response.json();
            if (reviews && reviews.length > 0) {
                // Clear existing placeholder slides
                track.innerHTML = '';
                
                // Build dynamic slides
                reviews.forEach(review => {
                    const card = document.createElement('div');
                    card.className = 'review-card';
                    
                    // Star rating
                    const stars = '★'.repeat(review.rating) + '☆'.repeat(5 - review.rating);
                    
                    // Photos HTML (if any)
                    let photosHTML = '';
                    if (review.photos && review.photos.length > 0) {
                        photosHTML = `<div class="review-photos" style="display: flex; gap: 8px; margin-top: 12px; margin-bottom: 8px;">`;
                        review.photos.forEach(photo => {
                            photosHTML += `<img src="${photo}" alt="Фото работы" style="width: 60px; height: 60px; object-fit: cover; border-radius: 6px; cursor: pointer;" onclick="window.open('${photo}', '_blank')">`;
                        });
                        photosHTML += `</div>`;
                    }
                    
                    const avatarLetter = review.name ? review.name.charAt(0).toUpperCase() : '?';
                    
                    card.innerHTML = `
                        <div>
                            <div class="review-stars">${stars}</div>
                            <p class="review-text">"${review.text}"</p>
                            ${photosHTML}
                            <div class="review-author">
                                <div class="author-avatar">${avatarLetter}</div>
                                <div class="author-info">
                                    <h4>${review.name}</h4>
                                    <span style="font-size: 12px; color: var(--color-text-muted);">${review.date || 'Клиент'}</span>
                                </div>
                            </div>
                        </div>
                    `;
                    track.appendChild(card);
                });
            }
        }
    } catch (e) {
        console.log("No dynamic reviews or failed to parse. Using fallback placeholder reviews.", e);
    }

    const cards = Array.from(track.children);
    let currentIndex = 0;
    const totalCards = cards.length;

    function getCardsPerView() {
        if (window.innerWidth >= 1024) return 3;
        if (window.innerWidth >= 768) return 2;
        return 1;
    }

    function updateSlider() {
        const cardsPerView = getCardsPerView();
        track.style.width = `${(totalCards / cardsPerView) * 100}%`;
        cards.forEach(card => {
            card.style.width = `${100 / totalCards}%`;
        });

        const maxIndex = totalCards - cardsPerView;
        if (currentIndex > maxIndex) {
            currentIndex = maxIndex;
        }

        const translateValue = (currentIndex * -100) / totalCards;
        track.style.transform = `translateX(${translateValue}%)`;
    }

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
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initReviewsSlider);
} else {
    initReviewsSlider();
}



// Smooth scroll for anchor links

document.querySelectorAll('a[href^="#"]').forEach(anchor => {

    anchor.addEventListener('click', function (e) {

        const targetId = this.getAttribute('href');

        if (targetId === '#') return;



        const targetElement = document.querySelector(targetId);

        if (targetElement) {

            e.preventDefault();

            targetElement.scrollIntoView({

                behavior: 'smooth'

            });

        }

    });

});



// Lightbox Logic

const lightbox = document.getElementById('lightbox');

const lightboxImg = document.getElementById('lightbox-img');

const lightboxClose = document.querySelector('.lightbox-close');



if (lightbox && lightboxImg && lightboxClose) {

    document.querySelectorAll('.lightbox-img').forEach(img => {

        img.addEventListener('click', (e) => {

            const fullSrc = e.target.getAttribute('data-full');

            if (fullSrc) {

                lightboxImg.src = fullSrc;

                lightbox.classList.add('active');

                document.body.style.overflow = 'hidden';

            }

        });

    });



    lightboxClose.addEventListener('click', () => {

        lightbox.classList.remove('active');

        document.body.style.overflow = '';

    });



    lightbox.addEventListener('click', (e) => {

        if (e.target === lightbox) {

            lightbox.classList.remove('active');

            document.body.style.overflow = '';

        }

    });



    document.addEventListener('keydown', (e) => {

        if (e.key === 'Escape' && lightbox.classList.contains('active')) {

            lightbox.classList.remove('active');

            document.body.style.overflow = '';

        }

    });

}



// FAQ Logic

document.querySelectorAll('.faq-question').forEach(button => {

    button.addEventListener('click', () => {

        const faqItem = button.parentElement;

        const isActive = faqItem.classList.contains('active');

        

        // Close all other FAQs

        document.querySelectorAll('.faq-item').forEach(item => {

            item.classList.remove('active');

            item.querySelector('.faq-answer').style.maxHeight = null;

        });



        // Open the clicked one if it wasn't active

        if (!isActive) {

            faqItem.classList.add('active');

            const answer = button.nextElementSibling;

            answer.style.maxHeight = answer.scrollHeight + 'px';

        }

    });

});



// Scroll Animations

const observerOptions = {

    root: null,

    rootMargin: '0px',

    threshold: 0.15

};



const observer = new IntersectionObserver((entries, observer) => {

    entries.forEach(entry => {

        if (entry.isIntersecting) {

            entry.target.classList.add('visible');

            observer.unobserve(entry.target);

        }

    });

}, observerOptions);



document.querySelectorAll('.fade-in').forEach(element => {

    observer.observe(element);

});



// Gallery Filter
document.addEventListener('DOMContentLoaded', () => {
    const filterButtons = document.querySelectorAll('.gallery-categories button');
    const galleryItems = document.querySelectorAll('.gallery-item');

    if (filterButtons.length > 0 && galleryItems.length > 0) {
        filterButtons.forEach(button => {
            button.addEventListener('click', () => {
                const filterValue = button.getAttribute('data-filter');
                
                // Toggle active class on buttons
                filterButtons.forEach(btn => btn.classList.remove('active'));
                button.classList.add('active');
                
                galleryItems.forEach(item => {
                    const category = item.getAttribute('data-category');
                    if (filterValue === 'all' || category === filterValue) {
                        item.classList.remove('hidden');
                    } else {
                        item.classList.add('hidden');
                    }
                });
            });
        });
    }
});
