import { Link, Navigate, Route, Routes } from "react-router-dom";
import { configCompleta } from "./config";
import AppShell from "./components/AppShell";
import { Marca, useColorDeBarra } from "./components/Acceso";
import EscenaReparto from "./components/EscenaReparto";
import ClienteApp from "./cliente/ClienteApp";
import RepartidorApp from "./repartidor/RepartidorApp";
import { Bolsa, Chevron, Moto } from "./components/iconos";
import { alClicConTransicion, useNavegarConTransicion } from "./transiciones";

// El ícono de la opción elegida es el que se transforma en el ícono del login.
function marcarIconoElegido(e) {
  e.currentTarget.querySelector(".puerta-icono").style.viewTransitionName = "icono-app";
}

function Puerta({ to, className, icono, titulo, detalle }) {
  const navegar = useNavegarConTransicion();
  return (
    <Link to={to} className={`puerta ${className}`} onClick={alClicConTransicion(navegar, to, marcarIconoElegido)}>
      <span className="puerta-icono">{icono}</span>
      <span className="puerta-texto">
        <strong>{titulo}</strong>
        <span>{detalle}</span>
      </span>
      <Chevron tam={20} />
    </Link>
  );
}

function Inicio() {
  useColorDeBarra("portada");

  return (
    <main className="portada">
      <Marca />

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
          <Puerta
            to="/cliente"
            className="tema-cliente puerta-principal"
            icono={<Bolsa tam={22} />}
            titulo="Hacer un pedido"
            detalle="Elegí un comercio y seguí tu pedido en vivo."
          />
          <Puerta
            to="/repartidor"
            className="tema-repartidor"
            icono={<Moto tam={22} />}
            titulo="Repartir pedidos"
            detalle="Aceptá pedidos cerca tuyo y entregalos con foto."
          />
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
          <AppShell app="cliente" titulo="Delivery" grupo="cliente" barra={false}>
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
