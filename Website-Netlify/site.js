// Progressive enhancement for index.html: local screenshot selection and enlargement.
// This script does not read app data, make API requests, or record analytics.

// Gallery tabs update the image, accessible description, and visible caption together.
// The keys match the HTML buttons' data-view values.
const image = document.querySelector('#gallery-image');
const caption = document.querySelector('#gallery-caption');
const views = {
  match: {
    src: 'assets/match-day.jpg',
    alt: 'PitchHarbor Match Day dashboard with the live lineup beside Smart Subs suggestions, the score, clock, and match controls.',
    caption: 'Your lineup beside Smart Subs, with essential match controls close at hand.'
  },
  field: {
    src: 'assets/full-pitch.jpg',
    alt: 'PitchHarbor full-screen soccer field with player positions, score, clock, and match controls.',
    caption: 'Give the pitch the whole workspace. Hide and restore controls whenever you need them.'
  },
  duo: {
    src: 'assets/duo-layout.jpg',
    alt: 'PitchHarbor divided Duo layout with the full field on the left and score, match controls, and Smart Subs on the right.',
    caption: 'In supported divided layouts, the field and controls occupy separate usable panels.'
  }
};

document.querySelectorAll('[data-view]').forEach(button => {
  button.addEventListener('click', () => {
    const view = views[button.dataset.view];
    document.querySelectorAll('[data-view]').forEach(other => {
      other.setAttribute('aria-pressed', String(other === button));
    });
    image.src = view.src;
    image.alt = view.alt;
    caption.textContent = view.caption;
  });
});

// Use the native dialog for modal focus behavior and Escape handling. Remember the
// opener so closing a screenshot returns keyboard users to their original control.
const dialog = document.querySelector('#image-dialog');
const enlarged = document.querySelector('#enlarged-image');
let opener;

document.querySelectorAll('[data-enlarge]').forEach(button => {
  button.addEventListener('click', () => {
    const source = button.querySelector('img');
    enlarged.src = source.src;
    enlarged.alt = source.alt;
    document.querySelector('#enlarged-caption').textContent = source.alt;
    opener = button;
    dialog.showModal();
  });
});

dialog.querySelector('.close-button').addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => {
  const bounds = dialog.getBoundingClientRect();
  // Only backdrop clicks close the dialog; clicks inside the image must leave it open.
  if (event.target === dialog && (
    event.clientX < bounds.left || event.clientX > bounds.right ||
    event.clientY < bounds.top || event.clientY > bounds.bottom
  )) {
    dialog.close();
  }
});
dialog.addEventListener('close', () => opener?.focus());
