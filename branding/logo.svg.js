// 產生 SVG:bg=true 為 App 圖示(含背景),bg=false 為透明背景的 App 內 logo
module.exports = (bg) => {
  const blade = `M 18,-98 C 150,-118 262,-205 286,-338 C 214,-342 120,-300 66,-236 C 36,-198 14,-150 -24,-104 Z`;
  const blades = [0,60,120,180,240,300].map(a => `<path d="${blade}" transform="rotate(${a})" fill="url(#bladeG)" />`).join('');
  const arm = `<g stroke="#ffffff" stroke-width="11" stroke-linecap="round" fill="none">
      <line x1="0" y1="0" x2="0" y2="-58"/><line x1="0" y1="-34" x2="-15" y2="-49"/><line x1="0" y1="-34" x2="15" y2="-49"/></g>`;
  const flake = [0,60,120,180,240,300].map(a => `<g transform="rotate(${a})">${arm}</g>`).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <radialGradient id="bgG" cx="35%" cy="28%" r="85%">
      <stop offset="0" stop-color="#2a3f8f"/><stop offset="0.55" stop-color="#121a45"/><stop offset="1" stop-color="#05060f"/>
    </radialGradient>
    <radialGradient id="glowG" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#46d4ff" stop-opacity="0.55"/><stop offset="1" stop-color="#46d4ff" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="bladeG" x1="0" y1="-340" x2="0" y2="-90" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#3b7bff"/><stop offset="0.55" stop-color="#7fe6ff"/><stop offset="1" stop-color="#f2fdff"/>
    </linearGradient>
    <linearGradient id="ringG" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#bff4ff"/><stop offset="0.5" stop-color="#46c8ff"/><stop offset="1" stop-color="#7a5cff"/>
    </linearGradient>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="6"/></filter>
  </defs>
  ${bg ? '<rect width="1024" height="1024" fill="url(#bgG)"/>' : ''}
  <circle cx="512" cy="512" r="440" fill="url(#glowG)"/>
  <circle cx="512" cy="512" r="398" fill="none" stroke="url(#ringG)" stroke-width="18" stroke-dasharray="757 76.5" stroke-linecap="round" transform="rotate(-80 512 512)"/>
  <g transform="translate(512 512) scale(0.84)">
    <g filter="url(#soft)" opacity="0.55">${blades}</g>
    ${blades}
    <circle r="112" fill="#0a1233" stroke="#9eeaff" stroke-width="8"/>
    ${flake}
  </g>
</svg>`;
};
