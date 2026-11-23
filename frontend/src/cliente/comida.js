// Imágenes y colores de cada comercio y producto. La API no trae fotos: se
// eligen por el nombre, con los emojis 3D de Fluent (licencia MIT, ver
// assets/LICENSE-fluentui-emoji.txt), los mismos de la moto del mapa.
import carne from "../assets/comida-cut_of_meat.png";
import plato from "../assets/comida-fork_and_knife_with_plate.png";
import pizza from "../assets/comida-pizza.png";
import queso from "../assets/comida-cheese_wedge.png";
import sushi from "../assets/comida-sushi.png";

const COMERCIOS = [
  [/pizz/i, { img: pizza, tinte: "#ffdccd" }],
  [/sushi/i, { img: sushi, tinte: "#ffdfe4" }],
  [/parrill|asado|carne/i, { img: carne, tinte: "#f6e1cf" }],
];
const OTRO_COMERCIO = { img: plato, tinte: "#e9ecf1" };

const PRODUCTOS = [
  [/pizza|muzza|fugaz|napolitana/i, pizza],
  [/sushi|roll|combinado|pieza|nigiri|sashimi/i, sushi],
  [/bife|chorizo|asado|vac[ií]o|entra[ñn]a|carne|lomo/i, carne],
  [/provoleta|queso/i, queso],
];

export function estiloComercio(nombre = "") {
  return COMERCIOS.find(([re]) => re.test(nombre))?.[1] || OTRO_COMERCIO;
}

// El producto usa su propia imagen; si el nombre no dice qué es, la del comercio.
export function imagenProducto(nombre = "", comercio = "") {
  return PRODUCTOS.find(([re]) => re.test(nombre))?.[1] || estiloComercio(comercio).img;
}

// "Av. Corrientes 1300, CABA" -> "Av. Corrientes 1300"
export const calle = (direccion = "") => direccion.split(",")[0].trim();

// "cliente.demo@example.com" -> "Cliente"
export function nombreDe(email = "") {
  const parte = email.split("@")[0].split(/[._-]/)[0] || "";
  return parte ? parte[0].toUpperCase() + parte.slice(1) : "";
}

// La última dirección de entrega queda en este navegador para proponerla en el
// próximo pedido. Es solo una comodidad: si no hay almacenamiento, se pide de nuevo.
const CLAVE_ENTREGA = "ultima-entrega-cliente";
export function ultimaEntrega() {
  try {
    const e = JSON.parse(localStorage.getItem(CLAVE_ENTREGA));
    return e && e.direccion && Number.isFinite(e.lat) && Number.isFinite(e.lng) ? e : null;
  } catch {
    return null;
  }
}
export function guardarEntrega(entrega) {
  try {
    localStorage.setItem(CLAVE_ENTREGA, JSON.stringify(entrega));
  } catch {
    /* sin almacenamiento: se vuelve a pedir la dirección */
  }
}
