import { useRef, useState } from 'react';
import { parseDecklist } from './lib/deck.js';
import { deriveTokens } from './lib/scryfall.js';
import {
  createSession,
  createToken,
  tapToken,
  destroyToken,
  untapAll,
  untapType,
} from './lib/session.js';
import { listDecks, saveDeck, touchDeck, newDeckId, corruptBackup } from './lib/storage.js';
import { artCandidates } from './lib/art.js';

const FLASH_MS = 140;
const TEN_MINUTES_MS = 10 * 60 * 1000;
const CAROUSEL_PAGE = 4;
const LONG_PRESS_MS = 500;

const PLACEHOLDER = `4 Lightning Bolt
4x Young Pyromancer
2 Fire // Ice (APC) 128
SB: 3 Pyroblast
// también acepta comentarios y encabezados`;

function nowIso() {
  return new Date().toISOString();
}

// Tap corto vs long-press. El long-press solo abre la vista expandida;
// no hace ninguna otra cosa en este producto.
// El temporizador y la bandera viven en refs: si el long-press provoca un
// re-render (abre la vista expandida), el pointerup posterior debe seguir
// viendo la bandera encendida, no un closure nuevo — de lo contrario soltar
// el dedo contaría además como tap sobre el token.
function usePress(onTap, onLongPress) {
  const timer = useRef(null);
  const fired = useRef(false);
  const cbs = useRef(null);
  cbs.current = { onTap, onLongPress };
  return {
    onPointerDown: () => {
      fired.current = false;
      clearTimeout(timer.current);
      timer.current = setTimeout(() => {
        fired.current = true;
        cbs.current.onLongPress();
      }, LONG_PRESS_MS);
    },
    onPointerUp: () => {
      clearTimeout(timer.current);
      if (!fired.current) cbs.current.onTap();
    },
    onPointerLeave: () => clearTimeout(timer.current),
    onPointerCancel: () => clearTimeout(timer.current),
    onContextMenu: (e) => e.preventDefault(),
  };
}

export default function App() {
  const [view, setView] = useState('home');
  const [flash, setFlash] = useState(false);

  const [store, setStore] = useState(() => listDecks());
  const decks = store.decks;

  // Alta de deck
  const [deckText, setDeckText] = useState('');
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState(null);
  const [error, setError] = useState(null);
  const [draft, setDraft] = useState(null); // {parsed, result, name, marks:Set}

  // Sesión (efímera: vive solo en memoria, recargar la cierra)
  const [play, setPlay] = useState(null); // {deck, carousel:[token], byId:Map}
  const [sess, setSess] = useState(null);
  const [page, setPage] = useState(0);
  const [expanded, setExpanded] = useState(null);
  const touchTimer = useRef(null);

  const goTo = (next) => {
    setFlash(true);
    setTimeout(() => {
      setView(next);
      setFlash(false);
    }, FLASH_MS);
  };

  function refreshDecks() {
    setStore(listDecks());
  }

  async function analyze() {
    setError(null);
    const parsed = parseDecklist(deckText);
    if (parsed.cards.length === 0) {
      setError('No se reconoció ninguna carta en el texto.');
      return;
    }
    setBusy(true);
    try {
      const result = await deriveTokens(
        parsed.cards.map((c) => c.name),
        setProgress
      );
      setDraft({
        parsed,
        result,
        name: '',
        marks: new Set(result.tokens.map((t) => t.oracleId)),
      });
      goTo('result');
    } catch (e) {
      // Si Scryfall falla a media consulta, se dice y no se guarda nada.
      setError(`La consulta a Scryfall falló: ${e.message}. No se guardó ningún catálogo parcial.`);
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  function saveDraft() {
    const deck = {
      id: newDeckId(),
      name: draft.name.trim(),
      createdAt: nowIso(),
      lastUsedAt: null,
      tokens: draft.result.tokens, // catálogo completo; la marca es solo para hoy
    };
    saveDeck(deck);
    refreshDecks();
    return deck;
  }

  function startSession(deck, marks = null) {
    const carousel = marks
      ? deck.tokens.filter((t) => marks.has(t.oracleId))
      : deck.tokens;
    setPlay({
      deck,
      carousel,
      byId: new Map(deck.tokens.map((t) => [t.oracleId, t])),
    });
    setSess(createSession());
    setPage(0);
    setExpanded(null);
    clearTimeout(touchTimer.current);
    // El último uso se escribe en cuanto la sesión pasa los diez minutos,
    // no al cerrarla — si solo se guardara al salir, nunca se guardaría.
    touchTimer.current = setTimeout(() => {
      touchDeck(deck.id, nowIso());
    }, TEN_MINUTES_MS);
    goTo('session');
  }

  return (
    <div className={`app${flash ? ' eink-flash' : ''}`}>
      {view === 'home' && (
        <HomeView
          decks={decks}
          broken={store.broken.length + (corruptBackup() ? 1 : 0)}
          onPlay={(deck) => startSession(deck)}
          onNew={() => {
            setDeckText('');
            setDraft(null);
            setError(null);
            goTo('paste');
          }}
          onLibrary={() => goTo('library')}
        />
      )}
      {view === 'library' && (
        <LibraryView decks={decks} onPlay={(deck) => startSession(deck)} onBack={() => goTo('home')} />
      )}
      {view === 'paste' && (
        <PasteView
          deckText={deckText}
          setDeckText={setDeckText}
          onAnalyze={analyze}
          onBack={() => goTo('home')}
          busy={busy}
          progress={progress}
          error={error}
        />
      )}
      {view === 'result' && draft && (
        <ResultView
          draft={draft}
          setDraft={setDraft}
          onBack={() => goTo('paste')}
          onSavePlay={() => startSession(saveDraft(), draft.marks)}
          onSaveExit={() => {
            saveDraft();
            goTo('home');
          }}
        />
      )}
      {view === 'session' && play && sess && (
        <SessionView
          play={play}
          sess={sess}
          setSess={setSess}
          page={page}
          setPage={setPage}
          onExpand={setExpanded}
          onExit={() => {
            clearTimeout(touchTimer.current);
            refreshDecks();
            goTo('home');
          }}
        />
      )}
      {expanded && <ExpandedView token={expanded} onClose={() => setExpanded(null)} />}
    </div>
  );
}

// ---- Inicio ----

function HomeView({ decks, broken, onPlay, onNew, onLibrary }) {
  const slots = decks.slice(0, 4);

  return (
    <div>
      <header className="topbar">
        <h1>PaperTokens</h1>
      </header>
      {broken > 0 && (
        <div className="status error">
          {broken} deck{broken > 1 ? 's' : ''} guardado{broken > 1 ? 's' : ''} no se
          pudo{broken > 1 ? 'ieron' : ''} leer. Los datos siguen en el navegador, no
          se sobrescriben.
        </div>
      )}
      {decks.length === 0 ? (
        <div className="empty-home">
          <p className="empty">No hay decks todavía.</p>
          <button className="primary" onClick={onNew}>
            Crear deck nuevo
          </button>
        </div>
      ) : (
        <>
          <div className="slots">
            {slots.map((d) => (
              <button key={d.id} className="slot" onClick={() => onPlay(d)}>
                <span className="slot-name">{d.name}</span>
                <span className="slot-sub">
                  {d.tokens.length} tokens
                  {d.lastUsedAt ? ` · usado ${d.lastUsedAt.slice(0, 10)}` : ''}
                </span>
              </button>
            ))}
            {Array.from({ length: 4 - slots.length }).map((_, i) => (
              <div key={i} className="slot vacant" aria-hidden="true" />
            ))}
          </div>
          <div className="home-exits">
            <button onClick={onLibrary}>Biblioteca</button>
            <button onClick={onNew}>Nuevo deck</button>
          </div>
        </>
      )}
    </div>
  );
}

// ---- Biblioteca (solo lectura) ----

function LibraryView({ decks, onPlay, onBack }) {
  return (
    <div>
      <header className="topbar">
        <button onClick={onBack}>←</button>
        <h1>Biblioteca</h1>
      </header>
      {decks.length === 0 ? (
        <p className="empty">No hay decks guardados.</p>
      ) : (
        <div className="slots">
          {decks.map((d) => (
            <button key={d.id} className="slot" onClick={() => onPlay(d)}>
              <span className="slot-name">{d.name}</span>
              <span className="slot-sub">
                {d.tokens.length} tokens
                {d.lastUsedAt ? ` · usado ${d.lastUsedAt.slice(0, 10)}` : ''}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ---- Alta: pegar ----

function PasteView({ deckText, setDeckText, onAnalyze, onBack, busy, progress, error }) {
  return (
    <div className="paste">
      <header className="topbar">
        <button onClick={onBack}>←</button>
        <h1>Nuevo deck</h1>
      </header>
      <p className="hint">Pega tu decklist. El sideboard cuenta como parte del mazo.</p>
      <textarea
        value={deckText}
        onChange={(e) => setDeckText(e.target.value)}
        placeholder={PLACEHOLDER}
        spellCheck={false}
      />
      <button className="primary" onClick={onAnalyze} disabled={busy || !deckText.trim()}>
        {busy ? 'Consultando Scryfall…' : 'Analizar'}
      </button>
      {busy && progress && (
        <div className="status">
          {progress.phase === 'cards' ? 'Buscando cartas' : 'Resolviendo tokens'} — lote{' '}
          {progress.batch}/{progress.total}
        </div>
      )}
      {error && <div className="status error">{error}</div>}
    </div>
  );
}

// ---- Alta: resultado ----

function ResultView({ draft, setDraft, onBack, onSavePlay, onSaveExit }) {
  const { parsed, result, name, marks } = draft;
  const unrecognized = parsed.skipped.filter((s) => s.reason === 'unrecognized');
  const canSave = name.trim().length > 0;

  function toggleMark(oracleId) {
    const next = new Set(marks);
    if (next.has(oracleId)) next.delete(oracleId);
    else next.add(oracleId);
    setDraft({ ...draft, marks: next });
  }

  return (
    <div>
      <header className="topbar">
        <button onClick={onBack}>←</button>
        <h1>Resultado</h1>
      </header>

      <input
        className="deck-name"
        type="text"
        value={name}
        placeholder="Nombre del deck"
        onChange={(e) => setDraft({ ...draft, name: e.target.value })}
      />

      <p className="stats">
        {result.foundCount} de {parsed.cards.length} cartas encontradas ·{' '}
        {result.tokens.length} tokens distintos. La marca decide qué entra al
        carrusel hoy; el deck guarda el catálogo completo.
      </p>

      {result.tokens.length === 0 ? (
        <p className="empty">Ninguna carta del mazo lista tokens en Scryfall.</p>
      ) : (
        <div className="pick-grid">
          {result.tokens.map((t) => (
            <div
              key={t.oracleId}
              className={`pick${marks.has(t.oracleId) ? ' marked' : ''}`}
              onClick={() => toggleMark(t.oracleId)}
            >
              <span className="pick-square">
                <TokenArt token={t} fallback={t.label} />
              </span>
              <span className="pick-label">{t.name}</span>
            </div>
          ))}
        </div>
      )}

      <div className="save-row">
        <button className="primary" onClick={onSavePlay} disabled={!canSave}>
          Guardar y jugar
        </button>
        <button onClick={onSaveExit} disabled={!canSave}>
          Guardar y salir
        </button>
      </div>

      {result.notFound.length > 0 && (
        <div className="section">
          <h2>No encontradas en Scryfall</h2>
          <ul>
            {result.notFound.map((n) => (
              <li key={n}>{n}</li>
            ))}
          </ul>
        </div>
      )}

      {unrecognized.length > 0 && (
        <div className="section">
          <h2>Líneas ignoradas por el parser</h2>
          <ul>
            {unrecognized.map((s) => (
              <li key={s.lineNumber}>
                L{s.lineNumber}: {s.line.trim()}
              </li>
            ))}
          </ul>
        </div>
      )}

      {result.suspects.length > 0 && (
        <div className="section">
          <h2>Mencionan crear tokens, sin entrada en all_parts</h2>
          <ul>
            {result.suspects.map((s) => (
              <li key={s.name}>
                {s.name}
                <span className="why">{s.oracleText}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

// ---- Sesión ----

function SessionView({ play, sess, setSess, page, setPage, onExpand, onExit }) {
  // 'reset' | 'exit' | null — ambas acciones piden confirmación en modal.
  const [confirm, setConfirm] = useState(null);
  const n = sess.active.length;
  const items = play.carousel;
  const pages = Math.ceil(items.length / CAROUSEL_PAGE);
  const paginated = pages > 1;
  const current = Math.min(page, pages - 1);
  const visible = paginated
    ? items.slice(current * CAROUSEL_PAGE, (current + 1) * CAROUSEL_PAGE)
    : items;

  return (
    <div className="session">
      <header className="session-header">
        <button className="header-btn" onClick={() => setConfirm('reset')}>
          Reiniciar partida
        </button>
        <button className="untap-all" onClick={() => setSess(untapAll)}>
          <span className="untap-icon">↺</span>
          <span className="untap-word">Untap all</span>
        </button>
        <button className="header-btn" onClick={() => setConfirm('exit')}>
          Salir
        </button>
      </header>

      {confirm && (
        <div className="modal-backdrop" onClick={() => setConfirm(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <p className="modal-text">
              {confirm === 'reset'
                ? '¿Seguro que deseas reiniciar? Se eliminan todos los tokens en juego.'
                : '¿Seguro que deseas salir? La sesión no se guarda.'}
            </p>
            <button
              className="primary"
              onClick={() => {
                setConfirm(null);
                if (confirm === 'reset') setSess(createSession());
                else onExit();
              }}
            >
              {confirm === 'reset' ? 'Reiniciar' : 'Salir'}
            </button>
            <button onClick={() => setConfirm(null)}>Cancelar</button>
          </div>
        </div>
      )}

      <div className={`active-zone n${Math.min(n, 4)}`}>
        {n === 0 && <p className="empty">Tap en el carrusel para poner un token en juego.</p>}
        {sess.active.map((entry) => (
          <Ficha
            key={entry.oracleId}
            token={play.byId.get(entry.oracleId)}
            entry={entry}
            onTapOne={() => setSess((s) => tapToken(s, entry.oracleId))}
            onPlus={() => setSess((s) => createToken(s, entry.oracleId))}
            onMinus={() => setSess((s) => destroyToken(s, entry.oracleId))}
            onUntapType={() => setSess((s) => untapType(s, entry.oracleId))}
            onExpand={onExpand}
          />
        ))}
      </div>

      <footer className="carousel">
        {paginated && (
          <button
            className="chevron"
            onClick={() => setPage((current - 1 + pages) % pages)}
          >
            &lt;
          </button>
        )}
        <div className="carousel-items">
          {visible.map((t) => {
            const inPlay = sess.active.some((e) => e.oracleId === t.oracleId);
            return (
              <div
                key={t.oracleId}
                className={`mini${inPlay ? ' in-play' : ''}`}
                onClick={() => setSess((s) => createToken(s, t.oracleId))}
              >
                <span className="mini-square">
                  <TokenArt token={t} fallback={t.initials} />
                </span>
                <span className="mini-label">{t.name}</span>
              </div>
            );
          })}
        </div>
        {paginated && (
          <button className="chevron" onClick={() => setPage((current + 1) % pages)}>
            &gt;
          </button>
        )}
      </footer>
    </div>
  );
}

function colorLetter(token) {
  return token.colors?.length ? token.colors.join('') : 'C';
}

// URLs de arte que ya fallaron en esta sesión: no se reintentan ni parpadean.
const missingArt = new Set();

// Intenta las rutas de public/tokens/ en orden; si ninguna existe, cae al
// placeholder (las letras de siempre).
function TokenArt({ token, fallback }) {
  const [urls] = useState(() => artCandidates(token).filter((u) => !missingArt.has(u)));
  const [i, setI] = useState(0);
  if (i >= urls.length) return fallback;
  return (
    <img
      className="token-art"
      src={urls[i]}
      alt={token.name}
      draggable={false}
      onError={() => {
        missingArt.add(urls[i]);
        setI(i + 1);
      }}
    />
  );
}

// En la vista mini sobra la palabra "Token": todo lo que hay en la mesa lo
// es. La expandida conserva la línea de tipo completa.
function shortTypeLine(token) {
  return token.typeLine.replace(/Token\s+/g, '');
}

function TrashIcon() {
  return (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <path
        fill="currentColor"
        d="M9 3h6v2h5v2H4V5h5V3zm-3 6h12l-1 12H7L6 9zm4 2.5v7h1.6v-7H10zm3 0v7h1.6v-7H13z"
      />
    </svg>
  );
}

function Ficha({ token, entry, onTapOne, onPlus, onMinus, onUntapType, onExpand }) {
  const handlers = usePress(onTapOne, () => onExpand(token));
  // Con el último token, el − es destruir del todo: bote de basura.
  const last = entry.untapped + entry.tapped === 1;

  return (
    <div className="ficha">
      <div className="pill">
        {entry.untapped > 0 && <span className="badge">{entry.untapped}</span>}
        {entry.tapped > 0 && <span className="badge is-tapped">{entry.tapped}</span>}
        <button className="pill-untap" onClick={onUntapType} aria-label={`Untap ${token.name}`}>
          ↺
        </button>
      </div>
      <div className="frame-row">
        <div className="card-box">
          <button className="orb orb-minus" onClick={onMinus} aria-label="Destruir un token">
            {last ? <TrashIcon /> : '−'}
          </button>
          <div className="card-frame" {...handlers}>
            <div className="title-bar">
              <span className="title-name">{token.name}</span>
              <span className="title-color">{colorLetter(token)}</span>
            </div>
            <div className="art-wrap">
              <div className="art-box">
                <TokenArt
                  token={token}
                  fallback={<span className="art-ph">{token.initials ?? token.label}</span>}
                />
              </div>
              {token.isCreature && token.power != null && (
                <span className="pt-badge">
                  {token.power}/{token.toughness}
                </span>
              )}
            </div>
            <div className="type-bar">{shortTypeLine(token)}</div>
            {!token.isCreature && token.oracleText && (
              <div className="mini-rules">{token.oracleText}</div>
            )}
          </div>
          <button className="orb orb-plus" onClick={onPlus} aria-label="Crear un token">
            +
          </button>
        </div>
      </div>
    </div>
  );
}

// ---- Vista expandida (solo lectura; se cierra con un tap en cualquier parte) ----

function ExpandedView({ token, onClose }) {
  return (
    <div className="expanded" onClick={onClose}>
      <div className="card-frame x-frame">
        <div className="title-bar">
          <span className="title-name">{token.name}</span>
          <span className="title-color">{colorLetter(token)}</span>
        </div>
        <div className="art-wrap">
          <div className="art-box">
            <TokenArt
              token={token}
              fallback={<span className="art-ph">{token.initials ?? token.label}</span>}
            />
          </div>
          {token.isCreature && token.power != null && (
            <span className="pt-badge">
              {token.power}/{token.toughness}
            </span>
          )}
        </div>
        <div className="type-bar">{token.typeLine}</div>
        <div className="rules-box">
          {(token.oracleText || 'Sin texto de reglas.').split('\n').map((line, i) => (
            <p key={i}>{line}</p>
          ))}
        </div>
      </div>
      <p className="expanded-hint">Tap en cualquier parte para cerrar</p>
    </div>
  );
}
