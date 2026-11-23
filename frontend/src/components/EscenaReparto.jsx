import moto from "../assets/moto.png";

// Ilustración de la portada: una calle que sale de un comercio y llega a una
// casa, con la moto en camino. Dibujada en SVG para que escale sin pixelarse;
// la moto es el mismo emoji 3D de Fluent (licencia MIT) que se usa en el mapa.
const CALLE = "M 404 96 C 404 186, 252 168, 246 252 S 132 330, 24 476";

function Arbol({ x, y, r }) {
  return (
    <g>
      <ellipse cx={x} cy={y + r + 4} rx={r * 0.9} ry={r * 0.25} className="escena-sombra" />
      <rect x={x - 2.5} y={y + r * 0.4} width="5" height={r * 0.7} rx="2" className="escena-tronco" />
      <circle cx={x} cy={y} r={r} className="escena-copa" />
      <circle cx={x - r * 0.3} cy={y - r * 0.3} r={r * 0.35} className="escena-copa-luz" />
    </g>
  );
}

export default function EscenaReparto() {
  return (
    <svg className="escena" viewBox="0 0 480 460" role="img" aria-label="Una moto de reparto en camino desde un comercio hasta una casa">
      <defs>
        <pattern id="toldo" width="14" height="14" patternUnits="userSpaceOnUse">
          <rect width="7" height="14" fill="#e2452b" />
          <rect x="7" width="7" height="14" fill="#ffffff" />
        </pattern>
      </defs>

      {/* calle */}
      <path d={CALLE} className="escena-calle-borde" transform="translate(0 7)" />
      <path d={CALLE} className="escena-calle" />
      <path d={CALLE} className="escena-calle-linea" />

      <Arbol x={300} y={112} r={15} />
      <Arbol x={452} y={286} r={19} />
      <Arbol x={346} y={372} r={14} />
      <Arbol x={190} y={404} r={21} />
      <Arbol x={28} y={190} r={13} />

      {/* comercio: de acá sale el pedido */}
      <g>
        <ellipse cx="410" cy="104" rx="62" ry="9" className="escena-sombra" />
        <polygon points="452,40 472,28 472,88 452,100" className="escena-lado" />
        <polygon points="360,40 380,28 472,28 452,40" className="escena-techo" />
        <rect x="360" y="40" width="92" height="60" className="escena-frente" />
        <rect x="355" y="50" width="102" height="13" rx="3" fill="url(#toldo)" />
        <rect x="397" y="72" width="18" height="28" rx="2" className="escena-puerta" />
        <rect x="368" y="72" width="20" height="14" rx="2" className="escena-ventana" />
        <rect x="424" y="72" width="20" height="14" rx="2" className="escena-ventana" />
      </g>

      {/* casa: el destino */}
      <g>
        <ellipse cx="92" cy="334" rx="58" ry="9" className="escena-sombra" />
        <polygon points="120,282 140,270 140,320 120,332" className="escena-lado" />
        <rect x="50" y="282" width="70" height="50" className="escena-frente" />
        <polygon points="43,285 85,248 127,285" className="escena-techo-casa" />
        <polygon points="85,248 127,285 146,272 106,238" className="escena-techo-casa-lado" />
        <rect x="77" y="305" width="15" height="27" rx="2" className="escena-puerta" />
        <rect x="58" y="296" width="13" height="12" rx="2" className="escena-ventana" />
        <rect x="99" y="296" width="13" height="12" rx="2" className="escena-ventana" />
      </g>
      <g className="escena-pin">
        <ellipse cx="86" cy="236" rx="9" ry="3" className="escena-sombra" />
        <path d="M86 232c-10-13-17-21-17-31a17 17 0 0 1 34 0c0 10-7 18-17 31Z" className="escena-pin-cuerpo" />
        <circle cx="86" cy="200" r="6.5" className="escena-pin-centro" />
      </g>

      {/* la moto, en camino */}
      <g className="escena-moto">
        <ellipse cx="250" cy="286" rx="60" ry="9" className="escena-sombra" />
        <image href={moto} x="178" y="148" width="148" height="148" />
      </g>
    </svg>
  );
}
