import caja from "../assets/pedido-caja.png";
import moto from "../assets/moto.png";

// La moto 3D según cómo va el pedido: buscando (con un radar), andando (con
// líneas de velocidad), o la caja cuando el pedido llegó, recién entró o se cayó.
// La moto mira a la izquierda: las líneas de velocidad quedan detrás, a la derecha.
export default function IlustracionEstado({ tipo }) {
  if (tipo === "entregado" || tipo === "recibido" || tipo === "fallido") {
    return (
      <div className={`ilus ilus-${tipo}`} aria-hidden="true">
        <img className="ilus-caja" src={caja} alt="" />
        <span className="ilus-sombra" />
      </div>
    );
  }
  return (
    <div className={`ilus ilus-${tipo}`} aria-hidden="true">
      {tipo === "buscando" && <span className="ilus-radar" />}
      <img className="ilus-moto" src={moto} alt="" />
      {tipo === "andando" && (
        <span className="ilus-viento">
          <i />
          <i />
          <i />
        </span>
      )}
      <span className="ilus-sombra" />
    </div>
  );
}
