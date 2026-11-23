import { useEffect } from "react";
import EscenaReparto from "./EscenaReparto";
import { Bolsa } from "./iconos";

// Color de fondo de la portada y de cada login (claro / oscuro). Lo usa la
// barra del navegador del celular para no cortar la pantalla con otro color.
export const FONDOS = {
  portada: ["#cdeedd", "#10291f"],
  cliente: ["#fde3d9", "#2a1712"],
  repartidor: ["#cdeedd", "#10291f"],
};

export function useColorDeBarra(clave) {
  useEffect(() => {
    const meta = document.querySelector('meta[name="theme-color"]');
    if (!meta) return undefined;
    const oscuro = window.matchMedia?.("(prefers-color-scheme: dark)").matches;
    const anterior = meta.getAttribute("content");
    meta.setAttribute("content", FONDOS[clave][oscuro ? 1 : 0]);
    return () => meta.setAttribute("content", anterior);
  }, [clave]);
}

export function Marca({ className = "" }) {
  return (
    <header className={`marca ${className}`}>
      <span className="marca-logo">
        <Bolsa tam={18} />
      </span>
      Delivery
    </header>
  );
}

// Pantalla de ingreso: la escena de la portada de fondo, difuminada y con el
// color de la app elegida, y una tarjeta adelante. En el celular la tarjeta es
// una hoja que sube desde abajo, como la de la portada.
export function PantallaAcceso({ app, children }) {
  useColorDeBarra(app);
  return (
    <main className={`acceso fondo-${app} tema-${app}`}>
      <div className="acceso-fondo">
        <div className="acceso-escena">
          <EscenaReparto animada={false} className="escena escena-fondo" decorativa />
        </div>
      </div>
      <Marca />
      <div className="acceso-cuerpo">
        <div className="acceso-tarjeta">{children}</div>
      </div>
    </main>
  );
}
