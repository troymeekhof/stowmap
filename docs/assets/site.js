// Stowmap site: plays the looping clips only while they are on screen, and not at all
// when the visitor asks for reduced motion (the poster stays up and the video gets controls).
(function () {
  var videos = [].slice.call(document.querySelectorAll('video[data-loop]'));
  if (!videos.length) return;
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)');

  function still(v) {
    v.removeAttribute('autoplay');
    v.pause();
    v.controls = true;
    if (v.currentTime > 0) v.load(); // back to the poster
  }
  function play(v) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }

  var io = 'IntersectionObserver' in window ? new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (reduce.matches) return;
      if (e.isIntersecting) play(e.target); else e.target.pause();
    });
  }, { threshold: 0.25 }) : null;

  function apply() {
    videos.forEach(function (v) {
      if (reduce.matches) { still(v); return; }
      v.controls = false;
      if (io) io.observe(v); else play(v);
    });
  }
  apply();
  if (reduce.addEventListener) reduce.addEventListener('change', apply);
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) videos.forEach(function (v) { v.pause(); });
    else if (!reduce.matches && io) videos.forEach(function (v) { io.unobserve(v); io.observe(v); });
  });
})();
