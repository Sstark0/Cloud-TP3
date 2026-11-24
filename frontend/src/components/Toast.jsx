import { useEffect, useState } from "react";
import { Check, Cruz } from "./iconos";

// Aviso flotante abajo de la pantalla: entra deslizándose, se va solo después
// de `duracion` ms y se puede cerrar tocándolo. `id` distingue un aviso nuevo
// con el mismo texto, para que vuelva a contar el tiempo.
export default function Toast({ aviso, onCerrar, duracion = 4500 }) {
  const [saliendo, setSaliendo] = useState(false);

  useEffect(() => {
    if (!aviso) return undefined;
    setSaliendo(false);
    const salir = setTimeout(() => setSaliendo(true), duracion);
    const cerrar = setTimeout(onCerrar, duracion + 300);
    return () => {
      clearTimeout(salir);
      clearTimeout(cerrar);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [aviso?.id]);

  if (!aviso) return null;
  const error = aviso.tipo === "error";
  return (
    <div className="toast-zona" role={error ? "alert" : "status"}>
      <button
        className={`toast${error ? " toast-error" : ""}${saliendo ? " saliendo" : ""}`}
        onClick={() => {
          setSaliendo(true);
          setTimeout(onCerrar, 250);
        }}
        aria-label={`${aviso.titulo}. Cerrar aviso`}
      >
        <span className="toast-icono" aria-hidden="true">
          {error ? <Cruz tam={18} /> : <Check tam={18} />}
        </span>
        <span className="toast-texto">
          <strong>{aviso.titulo}</strong>
          {aviso.detalle && <span>{aviso.detalle}</span>}
        </span>
      </button>
    </div>
  );
}
