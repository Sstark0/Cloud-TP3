import { useEffect } from "react";
import { Link, Navigate, Route, Routes } from "react-router-dom";
import { configCompleta } from "./config";
import AppShell from "./components/AppShell";
import EscenaReparto from "./components/EscenaReparto";
import ClienteApp from "./cliente/ClienteApp";
import RepartidorApp from "./repartidor/RepartidorApp";
import { Bolsa, Chevron, Moto } from "./components/iconos";

// En el celular, la barra del navegador toma el color de la portada.
function useColorDeBarra(color) {
  useEffect(() => {
    const meta = document.querySelector('meta[name="theme-color"]');
    if (!meta) return undefined;
    const anterior = meta.getAttribute("content");
    meta.setAttribute("content", color);
    return () => meta.setAttribute("content", anterior);
  }, [color]);
}

function Inicio() {
  const oscuro = typeof window !== "undefined" && window.matchMedia?.("(prefers-color-scheme: dark)").matches;
  useColorDeBarra(oscuro ? "#10291f" : "#cdeedd");

  return (
    <main className="portada">
      <header className="portada-marca">
        <span className="portada-logo">
          <Bolsa tam={18} />
        </span>
        Delivery
      </header>

      <div className="portada-cuerpo">
        <div className="portada-texto">
          <h1>Del local a tu puerta.</h1>
          <p>Pedí en los comercios de tu zona y seguí al repartidor en el mapa hasta que toque el timbre.</p>
        </div>

        <div className="portada-escena">
          <EscenaReparto />
        </div>

        <nav className="portada-hoja" aria-label="Elegí cómo usar la app">
          <h2>¿Cómo vas a usar la app?</h2>
          <Link to="/cliente" className="puerta tema-cliente puerta-principal">
            <span className="puerta-icono">
              <Bolsa tam={22} />
            </span>
            <span className="puerta-texto">
              <strong>Hacer un pedido</strong>
              <span>Elegí un comercio y seguí tu pedido en vivo.</span>
            </span>
            <Chevron tam={20} />
          </Link>
          <Link to="/repartidor" className="puerta tema-repartidor">
            <span className="puerta-icono">
              <Moto tam={22} />
            </span>
            <span className="puerta-texto">
              <strong>Repartir pedidos</strong>
              <span>Aceptá pedidos cerca tuyo y entregalos con foto.</span>
            </span>
            <Chevron tam={20} />
          </Link>
          <p className="portada-nota">Podés abrir las dos a la vez, en ventanas distintas.</p>
        </nav>
      </div>
    </main>
  );
}

function SinConfiguracion() {
  return (
    <main className="inicio">
      <h1>Falta la configuración</h1>
      <p>
        No está el archivo <code>frontend/.env.local</code>. Después del <code>terraform apply</code>, correr:
      </p>
      <pre>cd frontend{"\n"}npm run config{"\n"}npm run dev</pre>
      <p className="muted">
        Los usuarios de demo y sus contraseñas: <code>terraform -chdir=terraform/organization output -json usuarios_demo</code>.
      </p>
    </main>
  );
}

export default function App() {
  if (!configCompleta) return <SinConfiguracion />;
  return (
    <Routes>
      <Route path="/" element={<Inicio />} />
      <Route
        path="/cliente/*"
        element={
          <AppShell app="cliente" titulo="Delivery" grupo="cliente">
            <ClienteApp />
          </AppShell>
        }
      />
      <Route
        path="/repartidor/*"
        element={
          <AppShell app="repartidor" titulo="Delivery Repartidor" grupo="repartidor">
            <RepartidorApp />
          </AppShell>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
