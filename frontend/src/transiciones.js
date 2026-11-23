import { useCallback } from "react";
import { flushSync } from "react-dom";
import { useNavigate } from "react-router-dom";

// Transiciones entre pantallas con la View Transitions API del navegador: el
// navegador toma una foto de la pantalla actual, aplica el cambio y anima de
// una a otra. Los elementos con el mismo view-transition-name en las dos
// pantallas (la escena, la marca, la hoja de la portada y la tarjeta de login)
// se transforman uno en otro en vez de desaparecer y aparecer.
// Sin soporte (o con "reducir movimiento" activado) el cambio es inmediato.
export function conTransicion(cambio) {
  const reducir = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
  if (!document.startViewTransition || reducir) {
    cambio();
    return;
  }
  // flushSync: React tiene que dibujar la pantalla nueva dentro del callback,
  // para que el navegador la fotografíe ya actualizada.
  const transicion = document.startViewTransition(() => flushSync(cambio));
  // Si otra transición empieza antes de que termine esta, el navegador la
  // saltea (el cambio igual se aplica); no es un error.
  transicion.ready.catch(() => {});
  transicion.finished.catch(() => {});
}

export function useNavegarConTransicion() {
  const navegar = useNavigate();
  return useCallback((destino) => conTransicion(() => navegar(destino)), [navegar]);
}

// Para un <Link>: mantiene el href (abrir en otra pestaña sigue andando) y solo
// intercepta el clic normal.
export function alClicConTransicion(navegar, destino, antes) {
  return (e) => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    antes?.(e);
    navegar(destino);
  };
}
