import { useEffect, useMemo, useRef, useState } from "react";
import { Link, NavLink, Route, Routes, useLocation, useNavigate, useParams } from "react-router-dom";
import { api, ApiError } from "../api";
import { useSesion } from "../components/AppShell";
import Cuenta from "../components/Cuenta";
import IlustracionEstado from "../components/IlustracionEstado";
import { Cargando, ErrorAviso, Estado, Leyenda, Mapa, Pasos } from "../components/comunes";
import { Atras, Buscar, Casa, Chevron, Mira, Pin, Recibo, Reloj } from "../components/iconos";
import { config } from "../config";
import { buscarDireccion, direccionDe } from "../geocodificacion";
import { largo, restoDeRuta, rutaPorCalles } from "../ruteo";
import { alClicConTransicion, conTransicion, useNavegarConTransicion } from "../transiciones";
import { distancia, fechaHora, hora, parseFecha, precio, textoDistancia, textoMinutos, usePolling, useTick } from "../util";
import cajaVacia from "../assets/pedido-caja.png";
import { calle, estiloComercio, guardarEntrega, imagenProducto, nombreDe, ultimaEntrega } from "./comida";

const FINALES = ["ENTREGADO", "CANCELADO", "RECHAZADO"];

// Link que navega con transición (ver transiciones.js).
function Ir({ to, children, ...props }) {
  const navegar = useNavegarConTransicion();
  return (
    <Link to={to} {...props} onClick={alClicConTransicion(navegar, to)}>
      {children}
    </Link>
  );
}

function BotonVolver({ to, etiqueta }) {
  return (
    <Ir to={to} className="boton-circulo" aria-label={etiqueta}>
      <Atras tam={20} />
    </Ir>
  );
}

// Imagen del comercio: con el mismo nombre de transición en la tarjeta y en la
// cabecera del comercio, al entrar la comida "viaja" de una a la otra.
const nombreTransicion = (id) => ({ viewTransitionName: `comercio-${id}` });

// ---------------------------------------------------------------- inicio
function Saludo() {
  const { sesion } = useSesion();
  const entrega = ultimaEntrega();
  return (
    <header className="saludo">
      <div className="saludo-fila">
        <span className="saludo-pin" aria-hidden="true">
          <Pin tam={20} />
        </span>
        <span className="crece saludo-lugar">
          <span className="muted chico">Entregar en</span>
          <strong>{entrega ? calle(entrega.direccion) : "Elegís la dirección en el pedido"}</strong>
        </span>
        <Cuenta />
      </div>
      <p className="saludo-hola">Hola, {nombreDe(sesion.email)}</p>
      <h1 className="saludo-titulo">¿Qué querés comer hoy?</h1>
    </header>
  );
}

function PedidoEnCurso({ pedido }) {
  const { img, tinte } = estiloComercio(pedido.comercio);
  return (
    <Ir to={`pedidos/${pedido.id}`} className="en-curso" style={{ "--tinte": tinte }}>
      <span className="en-curso-img">
        <img src={img} alt="" />
      </span>
      <span className="crece">
        <span className="muted chico bloque">Tu pedido en {pedido.comercio}</span>
        <Estado estado={pedido.estado} />
      </span>
      <span className="en-curso-ir">
        Seguir <Chevron tam={16} />
      </span>
    </Ir>
  );
}

function Comercios() {
  const { app } = useSesion();
  const { datos, error, cargando, recargar } = usePolling(() => api(app, "GET", "/comercios"), 0);
  const activos = usePolling(() => api(app, "GET", "/pedidos"), 15000);
  const enCurso = (activos.datos || []).filter((p) => !FINALES.includes(p.estado));

  return (
    <section className="inicio-cliente">
      <Saludo />
      {enCurso.map((p) => (
        <PedidoEnCurso key={p.id} pedido={p} />
      ))}
      <h2 className="seccion-titulo">Comercios</h2>
      <ErrorAviso error={error} onReintentar={recargar} />
      {cargando && <Cargando />}
      <div className="grilla-comercios">
        {(datos || []).map((c) => {
          const { img, tinte } = estiloComercio(c.nombre);
          return (
            <Ir key={c.id} to={`comercios/${c.id}`} className="tarjeta-comercio" style={{ "--tinte": tinte }}>
              <span className="tarjeta-comercio-img">
                <img src={img} alt="" style={nombreTransicion(c.id)} />
              </span>
              <span className="tarjeta-comercio-texto">
                <strong>{c.nombre}</strong>
                <span className="muted chico">{calle(c.direccion)}</span>
              </span>
              <span className="tarjeta-comercio-pie">
                {c.tiempo_preparacion_min != null && (
                  <span className="chip">
                    <Reloj tam={14} /> ~{c.tiempo_preparacion_min} min
                  </span>
                )}
                <span className="boton-ir" aria-hidden="true">
                  <Chevron tam={18} />
                </span>
              </span>
            </Ir>
          );
        })}
      </div>
    </section>
  );
}

// ---------------------------------------------------------------- dirección de entrega
// El texto y el punto del mapa siempre describen el mismo lugar: escribir busca la
// dirección y mueve el pin; tocar el mapa, arrastrar el pin o usar la ubicación
// completan el texto con la dirección de ese punto.
function DireccionEntrega({ comercio, valor, onCambio }) {
  const [texto, setTexto] = useState(valor?.direccion || "");
  const [sugerencias, setSugerencias] = useState([]);
  const [buscando, setBuscando] = useState(false);
  const [error, setError] = useState(null);
  const consulta = useRef(0); // descarta respuestas viejas si llegan desordenadas
  const escrito = useRef(false); // solo se busca lo que tipeó la persona

  useEffect(() => {
    if (!escrito.current) return undefined;
    const q = texto.trim();
    if (q.length < 5) {
      setSugerencias([]);
      return undefined;
    }
    const id = setTimeout(async () => {
      const n = ++consulta.current;
      setBuscando(true);
      setError(null);
      try {
        const r = await buscarDireccion(q, comercio);
        if (n === consulta.current) {
          setSugerencias(r);
          if (!r.length) setError(new Error("No encontramos esa dirección. Probá con calle y altura, o marcala en el mapa."));
        }
      } catch (e) {
        if (n === consulta.current) setError(e);
      } finally {
        if (n === consulta.current) setBuscando(false);
      }
    }, 800);
    return () => clearTimeout(id);
  }, [texto, comercio]);

  function elegir(s) {
    escrito.current = false;
    setTexto(s.direccion);
    setSugerencias([]);
    setError(null);
    onCambio({ direccion: s.direccion, lat: s.lat, lng: s.lng });
  }

  async function marcar(punto) {
    escrito.current = false;
    consulta.current++;
    setSugerencias([]);
    setError(null);
    setBuscando(true);
    onCambio({ direccion: texto.trim(), ...punto });
    try {
      const direccion = await direccionDe(punto);
      if (direccion) {
        setTexto(direccion);
        onCambio({ direccion, ...punto });
      }
    } catch (e) {
      setError(e);
    } finally {
      setBuscando(false);
    }
  }

  function miUbicacion() {
    if (!navigator.geolocation) {
      setError(new Error("Este navegador no da la ubicación. Marcá el punto en el mapa."));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (p) => marcar({ lat: p.coords.latitude, lng: p.coords.longitude }),
      () => setError(new Error("No pudimos obtener tu ubicación. Marcá el punto en el mapa."))
    );
  }

  const puntos = [{ ...comercio, tipo: "comercio", etiqueta: comercio.nombre }];
  if (valor) puntos.push({ lat: valor.lat, lng: valor.lng, tipo: "destino", etiqueta: "Entrega" });

  return (
    <div className="entrega">
      <h3>¿Dónde lo entregamos?</h3>
      <div className="campo-direccion">
        <Buscar tam={18} className="campo-icono" />
        <input
          value={texto}
          placeholder="Calle y altura, por ejemplo Callao 100"
          aria-label="Dirección de entrega"
          autoComplete="off"
          onChange={(e) => {
            escrito.current = true;
            setTexto(e.target.value);
            if (valor) onCambio(null); // el punto anterior ya no corresponde al texto
          }}
        />
        {buscando && <span className="spinner campo-spinner" />}
        {sugerencias.length > 0 && (
          <ul className="sugerencias" role="listbox">
            {sugerencias.map((s, i) => (
              <li key={i}>
                <button type="button" onClick={() => elegir(s)}>
                  <Pin tam={16} /> {s.direccion}
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
      <ErrorAviso error={error} />
      <Mapa puntos={puntos} onClick={marcar} onArrastrar={marcar} alto={240} />
      <div className="fila-botones">
        <span className="muted chico">{valor ? "Podés arrastrar el pin para ajustar." : "También podés tocar el mapa."}</span>
        <button type="button" className="btn chico" onClick={miUbicacion}>
          <Mira tam={16} /> Mi ubicación
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- menú, carrito y pedido
// Hoja que sube al tocar un plato: imagen grande, precio, cantidad y el botón
// para sumarlo al pedido.
function HojaProducto({ producto, comercio, cantidadActual, onConfirmar, onCerrar }) {
  const [n, setN] = useState(cantidadActual || 1);
  const [cerrando, setCerrando] = useState(false);
  const caja = useRef(null);
  const { tinte } = estiloComercio(comercio.nombre);

  const cerrar = (despues) => {
    setCerrando(true);
    setTimeout(() => {
      despues?.();
      onCerrar();
    }, 220);
  };

  useEffect(() => {
    caja.current?.focus();
    const tecla = (e) => e.key === "Escape" && cerrar();
    window.addEventListener("keydown", tecla);
    return () => window.removeEventListener("keydown", tecla);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className={`hoja-modal-fondo${cerrando ? " cerrando" : ""}`} onClick={() => cerrar()}>
      <div
        ref={caja}
        tabIndex={-1}
        className="hoja-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="hoja-producto-titulo"
        style={{ "--tinte": tinte }}
        onClick={(e) => e.stopPropagation()}
      >
        <span className="hoja-asa" aria-hidden="true" />
        <div className="hoja-modal-img">
          <img src={imagenProducto(producto.nombre, comercio.nombre)} alt="" />
        </div>
        <h2 id="hoja-producto-titulo">{producto.nombre}</h2>
        <p className="muted">
          De {comercio.nombre}
          {comercio.tiempo_preparacion_min != null && ` · prepara en ~${comercio.tiempo_preparacion_min} min`}
        </p>
        <div className="hoja-modal-fila">
          <span className="precio-grande acento">{precio(producto.precio)}</span>
          <div className="contador grande" aria-label="Cantidad">
            <button className="btn redondo" onClick={() => setN((x) => Math.max(1, x - 1))} disabled={n <= 1} aria-label="Uno menos">
              −
            </button>
            <span aria-live="polite">{n}</span>
            <button className="btn redondo" onClick={() => setN((x) => x + 1)} aria-label="Uno más">
              +
            </button>
          </div>
        </div>
        <div className="hoja-modal-pie">
          <span className="hoja-modal-total">
            <span className="muted chico">Total</span>
            <span className="precio-grande">{precio(n * producto.precio)}</span>
          </span>
          <button className="btn primario" onClick={() => cerrar(() => onConfirmar(n))}>
            {cantidadActual ? "Actualizar pedido" : "Agregar al pedido"}
          </button>
        </div>
        {cantidadActual > 0 && (
          <button className="btn-texto quitar" onClick={() => cerrar(() => onConfirmar(0))}>
            Quitar del pedido
          </button>
        )}
      </div>
    </div>
  );
}

function Comercio() {
  const { app } = useSesion();
  const { id } = useParams();
  const comercioId = Number(id); // los ids de comercio y producto son enteros
  const navigate = useNavigate();
  const comercios = usePolling(() => api(app, "GET", "/comercios"), 0);
  const productos = usePolling(() => api(app, "GET", `/comercios/${comercioId}/productos`), 0, [comercioId]);
  const comercio = (comercios.datos || []).find((c) => c.id === comercioId);
  // Lo genera el cliente: si el POST se reintenta, la cola FIFO lo deduplica por este id.
  const [pedidoId] = useState(() => crypto.randomUUID());

  const [carrito, setCarrito] = useState({});
  const [entrega, setEntrega] = useState(ultimaEntrega); // { direccion, lat, lng }
  const [abierto, setAbierto] = useState(null); // producto en la hoja
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState(null);

  const lista = productos.datos || [];
  const items = Object.entries(carrito)
    .filter(([, n]) => n > 0)
    .map(([pid, n]) => [Number(pid), n]);
  const unidades = items.reduce((s, [, n]) => s + n, 0);
  const total = items.reduce((s, [pid, n]) => s + n * Number(lista.find((p) => p.id === pid)?.precio || 0), 0);
  const fijar = (pid, n) => setCarrito((c) => ({ ...c, [pid]: n }));
  const listo = Boolean(entrega?.direccion && Number.isFinite(entrega?.lat));
  const { img, tinte } = estiloComercio(comercio?.nombre);

  async function pedir() {
    setEnviando(true);
    setError(null);
    try {
      const r = await api(app, "POST", "/pedidos", {
        pedido_id: pedidoId,
        comercio_id: comercioId,
        items: items.map(([producto_id, cantidad]) => ({ producto_id, cantidad })),
        entrega: { direccion: entrega.direccion, lat: entrega.lat, lng: entrega.lng },
      });
      guardarEntrega(entrega);
      conTransicion(() => navigate(`/cliente/pedidos/${r.pedido_id}`));
    } catch (e) {
      setError(e);
      setEnviando(false);
    }
  }

  return (
    <section className={`detalle-comercio${items.length ? " con-barra-pedido" : ""}`}>
      <div className="hero-comercio" style={{ "--tinte": tinte }}>
        <BotonVolver to="/cliente" etiqueta="Volver a los comercios" />
        <img className="hero-comercio-img" src={img} alt="" style={nombreTransicion(comercioId)} />
        <h1>{comercio?.nombre || "…"}</h1>
        {comercio && (
          <p className="hero-comercio-datos">
            <span>{calle(comercio.direccion)}</span>
            {comercio.tiempo_preparacion_min != null && (
              <span className="chip">
                <Reloj tam={14} /> prepara en ~{comercio.tiempo_preparacion_min} min
              </span>
            )}
          </p>
        )}
      </div>

      <div className="carta">
        <h2 className="seccion-titulo">La carta</h2>
        <ErrorAviso error={productos.error} onReintentar={productos.recargar} />
        {productos.cargando && <Cargando />}
        <div className="lista-platos">
          {lista.map((p) => (
            <button key={p.id} className={`tarjeta-plato${carrito[p.id] ? " elegido" : ""}`} onClick={() => setAbierto(p)}>
              <span className="tarjeta-plato-texto">
                <strong>{p.nombre}</strong>
                <span className="precio-grande">{precio(p.precio)}</span>
                <span className="tarjeta-plato-accion">{carrito[p.id] ? `${carrito[p.id]} en tu pedido` : "Agregar"}</span>
              </span>
              <span className="tarjeta-plato-img" style={{ "--tinte": tinte }}>
                <img src={imagenProducto(p.nombre, comercio?.nombre)} alt="" />
              </span>
            </button>
          ))}
        </div>

        {items.length > 0 && comercio && (
          <>
            <div className="resumen-pedido">
              <h3>Tu pedido</h3>
              {items.map(([pid, n]) => {
                const p = lista.find((x) => x.id === pid);
                return (
                  p && (
                    <button key={pid} className="resumen-fila" onClick={() => setAbierto(p)}>
                      <span>
                        <span className="monto">{n}×</span> {p.nombre}
                      </span>
                      <span className="monto">{precio(n * p.precio)}</span>
                    </button>
                  )
                );
              })}
            </div>
            <DireccionEntrega comercio={comercio} valor={entrega} onCambio={setEntrega} />
            <ErrorAviso error={error} />
          </>
        )}
      </div>

      {items.length > 0 && comercio && (
        <div className="barra-pedido">
          <div className="barra-pedido-resumen">
            <span className="muted chico">
              {unidades} {unidades === 1 ? "producto" : "productos"}
            </span>
            <span className="monto fuerte">{precio(total)}</span>
          </div>
          <button className="btn primario" onClick={pedir} disabled={enviando || !listo}>
            {enviando ? "Enviando…" : listo ? "Hacer el pedido" : "Falta la dirección"}
          </button>
        </div>
      )}

      {abierto && comercio && (
        <HojaProducto
          key={abierto.id}
          producto={abierto}
          comercio={comercio}
          cantidadActual={carrito[abierto.id] || 0}
          onConfirmar={(n) => fijar(abierto.id, n)}
          onCerrar={() => setAbierto(null)}
        />
      )}
    </section>
  );
}

// ---------------------------------------------------------------- mis pedidos
function Pedidos() {
  const { app } = useSesion();
  const { datos, error, cargando, recargar } = usePolling(() => api(app, "GET", "/pedidos"), 10000);
  const enCurso = (datos || []).filter((p) => !FINALES.includes(p.estado));
  const anteriores = (datos || []).filter((p) => FINALES.includes(p.estado));

  return (
    <section className="mis-pedidos">
      <h1 className="pantalla-titulo">Mis pedidos</h1>
      <ErrorAviso error={error} onReintentar={recargar} />
      {cargando && <Cargando />}

      {datos?.length === 0 && (
        <div className="vacio">
          <img src={cajaVacia} alt="" width="96" height="96" />
          <p>Todavía no hiciste pedidos.</p>
          <Ir to="/cliente" className="btn primario">
            Ver comercios
          </Ir>
        </div>
      )}

      {enCurso.length > 0 && (
        <>
          <h2 className="seccion-titulo">En curso</h2>
          {enCurso.map((p) => {
            const { img, tinte } = estiloComercio(p.comercio);
            return (
              <Ir key={p.id} to={p.id} className="pedido-activo" style={{ "--tinte": tinte }}>
                <span className="pedido-activo-cabecera">
                  <span className="pedido-img">
                    <img src={img} alt="" />
                  </span>
                  <span className="crece">
                    <strong>{p.comercio}</strong>
                    <span className="muted chico bloque">
                      {fechaHora(p.creado_en)} · <span className="monto">{precio(p.total)}</span>
                    </span>
                  </span>
                </span>
                <Pasos estado={p.estado} />
                <span className="pedido-activo-ir">
                  Seguir el pedido <Chevron tam={16} />
                </span>
              </Ir>
            );
          })}
        </>
      )}

      {anteriores.length > 0 && (
        <>
          <h2 className="seccion-titulo">Anteriores</h2>
          <div className="lista-pedidos">
            {anteriores.map((p) => {
              const { img, tinte } = estiloComercio(p.comercio);
              return (
                <Ir key={p.id} to={p.id} className="fila-pedido" style={{ "--tinte": tinte }}>
                  <span className="pedido-img chica">
                    <img src={img} alt="" />
                  </span>
                  <span className="crece">
                    <strong>{p.comercio}</strong>
                    <span className="muted chico bloque">
                      {fechaHora(p.creado_en)} ·{" "}
                      {p.estado === "RECHAZADO" ? "sin cargo" : <span className="monto">{precio(p.total)}</span>}
                    </span>
                  </span>
                  {p.calificacion ? (
                    <span className="chip calificacion-chip" aria-label={`Calificado con ${p.calificacion} de 5`}>
                      ★ {p.calificacion}
                    </span>
                  ) : (
                    <Estado estado={p.estado} />
                  )}
                </Ir>
              );
            })}
          </div>
        </>
      )}
    </section>
  );
}

// ---------------------------------------------------------------- seguimiento
const VELOCIDAD_DEFECTO = 25 / 3.6; // m/s, por si todavía no hay posiciones para medirla
const RADIO_RETIRO_M = 60;

// Recorrido del repartidor visto desde esta pantalla: guarda cada posición nueva
// que llega por el polling (y la conserva en sessionStorage si se recarga).
// La API solo devuelve la última posición; el historial completo se archiva en S3.
function useRecorrido(id, pedido) {
  const clave = `recorrido-${id}`;
  const [recorrido, setRecorrido] = useState(() => {
    try {
      return JSON.parse(sessionStorage.getItem(clave)) || [];
    } catch {
      return [];
    }
  });
  const marca = pedido?.repartidor_actualizado_en;
  useEffect(() => {
    if (!marca || pedido.repartidor_lat == null) return;
    const t = parseFecha(marca)?.getTime();
    setRecorrido((r) => {
      if (r.length && r[r.length - 1].t === t) return r;
      const nuevo = [...r, { lat: pedido.repartidor_lat, lng: pedido.repartidor_lng, t }].slice(-500);
      try {
        sessionStorage.setItem(clave, JSON.stringify(nuevo));
      } catch {
        /* sin almacenamiento: el recorrido vive solo en memoria */
      }
      return nuevo;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [marca]);
  return recorrido;
}

const DESVIO_MAX_M = 150; // si el repartidor se aparta más de la ruta, se pide una nueva

// Lo que le falta al repartidor: si todavía no pasó por el comercio, primero va
// a retirar. La ruta va por calles (OSRM); mientras llega, o si el servicio no
// responde, se usa la línea recta.
// Ruta por calles entre `paradas`, pedida una vez por `clave` (null = no hace falta).
function useRuta(paradas, clave) {
  const [ruta, setRuta] = useState(null);
  useEffect(() => {
    if (!clave) return undefined;
    let vigente = true;
    rutaPorCalles(paradas).then((puntos) => vigente && setRuta(puntos ? { clave, puntos } : null));
    return () => {
      vigente = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clave]);
  return clave && ruta?.clave === clave ? ruta.puntos : null;
}

function useViaje(pedido, recorrido) {
  const enCamino = pedido?.estado === "ASIGNADO" && pedido.repartidor_lat != null;
  const rep = enCamino ? { lat: pedido.repartidor_lat, lng: pedido.repartidor_lng } : null;
  const comercio = enCamino ? { lat: pedido.comercio_lat, lng: pedido.comercio_lng } : null;
  const destino = enCamino ? { lat: pedido.entrega_lat, lng: pedido.entrega_lng } : null;
  const retirado =
    enCamino && (recorrido.some((p) => distancia(p, comercio) < RADIO_RETIRO_M) || distancia(rep, comercio) < RADIO_RETIRO_M);

  // Dos tramos con rutas separadas. Si fuera una sola ruta repartidor -> comercio
  // -> entrega, cuando el repartidor esta entre el comercio y el cliente la ruta
  // pasa dos veces por las mismas calles, y ubicarlo sobre ella podia elegir el
  // tramo de la vuelta: la distancia crecia mientras iba a retirar.
  // - Tramo actual: donde esta el repartidor hasta su proxima parada. Es el
  //   unico sobre el que se lo ubica, y se recalcula si se aparta.
  // - Tramo siguiente (solo antes de retirar): comercio -> entrega, completo.
  const [recalculos, setRecalculos] = useState(0);
  const proxima = retirado ? destino : comercio;
  const rutaActual = useRuta(enCamino ? [rep, proxima] : null, enCamino ? `${pedido.id}:${retirado}:${recalculos}` : null);
  const rutaSiguiente = useRuta(enCamino && !retirado ? [comercio, destino] : null, enCamino && !retirado ? `${pedido.id}:entrega` : null);

  const resto = enCamino && rutaActual ? restoDeRuta(rutaActual, rep) : null;
  const desviado = resto != null && resto.desvio > DESVIO_MAX_M;
  useEffect(() => {
    if (desviado) setRecalculos((n) => n + 1);
  }, [desviado]);
  if (!enCamino) return null;

  const actual = resto && !desviado ? resto.puntos : [rep, proxima];
  const siguiente = retirado ? [] : rutaSiguiente || [comercio, destino];
  const pendiente = [...actual, ...siguiente.slice(1)];
  const metros = largo(pendiente);

  // Velocidad medida con las posiciones del último minuto.
  const ultimo = recorrido[recorrido.length - 1];
  const tramo = ultimo ? recorrido.filter((p) => ultimo.t - p.t <= 60000) : [];
  let velocidad = VELOCIDAD_DEFECTO;
  if (tramo.length > 1) {
    const s = (tramo[tramo.length - 1].t - tramo[0].t) / 1000;
    if (s > 0 && largo(tramo) / s > 1) velocidad = largo(tramo) / s;
  }
  return { retirado, pendiente, metros, segundos: metros / velocidad, porCalles: Boolean(resto && !desviado) };
}

function Estrellas({ puntaje }) {
  return (
    <span className="estrellas-fijas" aria-label={`${puntaje} de 5`}>
      {[1, 2, 3, 4, 5].map((n) => (
        <span key={n} className={n <= puntaje ? "activa" : ""} aria-hidden="true">
          ★
        </span>
      ))}
    </span>
  );
}

// La calificación queda en la tabla calificacion; GET /pedidos/{id} la devuelve,
// así que un pedido ya calificado la muestra en vez de volver a pedirla.
function Calificar({ pedido }) {
  const { app } = useSesion();
  const [puntaje, setPuntaje] = useState(0);
  const [comentario, setComentario] = useState("");
  const [estado, setEstado] = useState(null); // null | "enviando" | Error
  const [guardada, setGuardada] = useState(
    pedido.calificacion ? { puntaje: pedido.calificacion, comentario: pedido.calificacion_comentario } : null
  );

  async function enviar() {
    setEstado("enviando");
    try {
      await api(app, "POST", `/pedidos/${pedido.id}/calificacion`, { puntaje, comentario: comentario || undefined });
      setGuardada({ puntaje, comentario });
    } catch (e) {
      setEstado(e);
    }
  }

  if (guardada)
    return (
      <div className="tarjeta calificada">
        <span className="muted chico">Tu calificación</span>
        <Estrellas puntaje={guardada.puntaje} />
        {guardada.comentario && <p className="calificada-comentario">“{guardada.comentario}”</p>}
      </div>
    );
  return (
    <div className="tarjeta">
      <h3>¿Cómo estuvo la entrega?</h3>
      <div className="estrellas" role="radiogroup" aria-label="Puntaje">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            className={n <= puntaje ? "activa" : ""}
            onClick={() => setPuntaje(n)}
            role="radio"
            aria-checked={n === puntaje}
            aria-label={`${n} de 5`}
          >
            ★
          </button>
        ))}
      </div>
      <textarea placeholder="Comentario (opcional)" value={comentario} onChange={(e) => setComentario(e.target.value)} />
      {estado instanceof Error && <ErrorAviso error={estado} />}
      <button className="btn primario ancho" disabled={!puntaje || estado === "enviando"} onClick={enviar}>
        Enviar calificación
      </button>
    </div>
  );
}

const reloj = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

function TiempoBuscando({ desde }) {
  useTick(1000);
  const limite = config.esperaRepartidorSegundos;
  const lleva = desde ? Math.max(0, (Date.now() - desde) / 1000) : 0;
  return (
    <>
      Lleva <span className="monto">{reloj(lleva)}</span>. Si en <span className="monto">{reloj(limite)}</span> no aparece
      ninguno, el pedido se cancela.
    </>
  );
}

// Estado del envío, como "Delivery status": la moto, qué está pasando y el progreso.
function EstadoEntrega({ pedido, viaje }) {
  const estado = pedido?.estado || "RECIBIDO";
  let tipo, titulo, detalle;
  if (estado === "RECIBIDO") {
    [tipo, titulo, detalle] = ["recibido", "Recibimos tu pedido", "Lo estamos registrando…"];
  } else if (estado === "CREADO") {
    [tipo, titulo, detalle] = ["buscando", "Buscando repartidor", <TiempoBuscando desde={parseFecha(pedido.creado_en)} />];
  } else if (estado === "ASIGNADO") {
    tipo = "andando";
    titulo = viaje?.retirado ? "Tu pedido va en camino" : "El repartidor va a buscar tu pedido";
    detalle = viaje ? (
      <>
        A <span className="monto">{textoDistancia(viaje.metros)}</span> · llega en ~
        <span className="monto">{textoMinutos(viaje.segundos)}</span>
      </>
    ) : (
      "Esperando la ubicación del repartidor…"
    );
  } else if (estado === "ENTREGADO") {
    [tipo, titulo, detalle] = ["entregado", "¡Llegó tu pedido!", "Que lo disfrutes."];
  } else if (estado === "CANCELADO") {
    [tipo, titulo, detalle] = ["fallido", "Pedido cancelado", "No conseguimos un repartidor para este pedido."];
  } else {
    [tipo, titulo, detalle] = ["fallido", "El comercio no pudo tomarlo", "Algún producto ya no está disponible. No se te cobró."];
  }
  return (
    <div className={`estado-entrega estado-entrega-${tipo}`} aria-live="polite">
      <IlustracionEstado tipo={tipo} />
      <h2>{titulo}</h2>
      <p>{detalle}</p>
      <Pasos estado={estado} />
    </div>
  );
}

function Seguimiento() {
  const { app } = useSesion();
  const { id } = useParams();
  const [final, setFinal] = useState(false);
  const { datos: pedido, error, recargar } = usePolling(
    async () => {
      try {
        const p = await api(app, "GET", `/pedidos/${id}`);
        if (FINALES.includes(p.estado)) setFinal(true);
        return p;
      } catch (e) {
        // Recién encolado: el workflow todavía no lo registró en la base.
        if (e instanceof ApiError && e.status === 404) return null;
        throw e;
      }
    },
    final ? 0 : 4000,
    [id]
  );

  const recorrido = useRecorrido(id, pedido);
  const v = useViaje(pedido, recorrido);
  const puntos = useMemo(() => {
    if (!pedido) return [];
    const p = [
      { lat: pedido.comercio_lat, lng: pedido.comercio_lng, tipo: "comercio", etiqueta: pedido.comercio },
      { lat: pedido.entrega_lat, lng: pedido.entrega_lng, tipo: "destino", etiqueta: "Entrega" },
    ];
    if (pedido.repartidor_lat != null)
      p.push({ lat: pedido.repartidor_lat, lng: pedido.repartidor_lng, tipo: "repartidor", etiqueta: "Repartidor" });
    return p;
  }, [pedido]);

  if (pedido === undefined) return error ? <ErrorAviso error={error} onReintentar={recargar} /> : <Cargando />;

  if (pedido === null)
    return (
      <section>
        <div className="cabecera-seguimiento">
          <BotonVolver to="/cliente/pedidos" etiqueta="Volver a mis pedidos" />
          <h1>Tu pedido</h1>
        </div>
        <EstadoEntrega pedido={null} />
      </section>
    );

  const rechazado = pedido.estado === "RECHAZADO";
  const trazos = [{ puntos: recorrido, tipo: "hecho" }];
  if (v) trazos.push({ puntos: v.pendiente, tipo: "pendiente" });

  const posHace = pedido.repartidor_actualizado_en
    ? Math.round((Date.now() - parseFecha(pedido.repartidor_actualizado_en)) / 1000)
    : null;

  return (
    <section>
      <div className="cabecera-seguimiento">
        <BotonVolver to="/cliente/pedidos" etiqueta="Volver a mis pedidos" />
        <h1>{pedido.comercio}</h1>
      </div>
      <EstadoEntrega pedido={pedido} viaje={v} />
      <ErrorAviso error={error} />

      {!rechazado && (
        <>
          <Mapa puntos={puntos} trazos={trazos} />
          <div className="fila-botones">
            <Leyenda
              items={[
                { tipo: "comercio", texto: "Comercio" },
                { tipo: "destino", texto: "Entrega" },
                { tipo: "repartidor", texto: "Repartidor" },
                ...(recorrido.length > 1 ? [{ tipo: "linea-hecho", texto: "Recorrido" }] : []),
                ...(v ? [{ tipo: "linea-pendiente", texto: "Por recorrer" }] : []),
              ]}
            />
            {posHace != null && <span className="muted chico">Posición de hace {posHace} s</span>}
          </div>
        </>
      )}

      {pedido.estado === "ENTREGADO" && <Calificar pedido={pedido} />}

      <div className="comanda">
        <div className="comanda-cabecera">
          <span>Pedido</span>
          <span className="monto">#{pedido.id.slice(0, 8)}</span>
        </div>
        {pedido.items.map((i) => (
          <div key={i.producto_id} className="comanda-fila">
            <span>
              <span className="monto">{i.cantidad}×</span> {i.nombre}
            </span>
            <span className="monto">{precio(i.cantidad * i.precio_unitario)}</span>
          </div>
        ))}
        <div className="comanda-fila total">
          <span>Total</span>
          {rechazado ? <span>Sin cargo</span> : <span className="monto">{precio(pedido.total)}</span>}
        </div>
        <div className="comanda-pie">
          <Pin tam={15} /> {pedido.direccion_entrega}
        </div>
        <ol className="comanda-historial">
          {pedido.eventos.map((e, i) => (
            <li key={i}>
              <span className="monto">{hora(e.creado_en)}</span> <Estado estado={e.estado} />
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}

function NavCliente() {
  const { pathname } = useLocation();
  const navegar = useNavegarConTransicion();
  // En la pantalla de un comercio la barra del pedido ocupa ese lugar.
  if (/\/cliente\/comercios\//.test(pathname)) return null;
  return (
    <nav className="nav-cliente" aria-label="Secciones">
      <NavLink to="/cliente" end onClick={alClicConTransicion(navegar, "/cliente")}>
        <Casa tam={20} /> Inicio
      </NavLink>
      <NavLink to="/cliente/pedidos" onClick={alClicConTransicion(navegar, "/cliente/pedidos")}>
        <Recibo tam={20} /> Mis pedidos
      </NavLink>
    </nav>
  );
}

export default function ClienteApp() {
  return (
    <>
      <NavCliente />
      <Routes>
        <Route index element={<Comercios />} />
        <Route path="comercios/:id" element={<Comercio />} />
        <Route path="pedidos" element={<Pedidos />} />
        <Route path="pedidos/:id" element={<Seguimiento />} />
      </Routes>
    </>
  );
}
