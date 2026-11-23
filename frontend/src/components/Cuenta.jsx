import { useEffect, useRef, useState } from "react";
import { nombreDe } from "../cliente/comida";
import { useSesion } from "./AppShell";
import { Salir } from "./iconos";

// Avatar con la inicial; al tocarlo muestra el email y el botón para salir.
export default function Cuenta() {
  const { sesion, salir } = useSesion();
  const [abierta, setAbierta] = useState(false);
  const caja = useRef(null);
  const nombre = nombreDe(sesion.email);

  useEffect(() => {
    if (!abierta) return undefined;
    const fuera = (e) => !caja.current?.contains(e.target) && setAbierta(false);
    const tecla = (e) => e.key === "Escape" && setAbierta(false);
    document.addEventListener("pointerdown", fuera);
    window.addEventListener("keydown", tecla);
    return () => {
      document.removeEventListener("pointerdown", fuera);
      window.removeEventListener("keydown", tecla);
    };
  }, [abierta]);

  return (
    <div className="cuenta-menu" ref={caja}>
      <button className="saludo-avatar" onClick={() => setAbierta((a) => !a)} aria-expanded={abierta} aria-label="Tu cuenta">
        {nombre.slice(0, 1) || "?"}
      </button>
      {abierta && (
        <div className="cuenta-popover" role="menu">
          <span className="muted chico">{sesion.email}</span>
          <button className="btn ancho" role="menuitem" onClick={salir}>
            <Salir tam={18} /> Salir
          </button>
        </div>
      )}
    </div>
  );
}
