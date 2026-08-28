import { useState } from 'react';
import { parseDecklist } from './lib/deck.js';
import { deriveTokens } from './lib/scryfall.js';
import { iconKey, isPackaged } from './lib/icons.js';
import { buildFile, downloadFile, fileName } from './lib/export.js';
import { iconCandidates } from './lib/art.js';

const PLACEHOLDER = `4 Lightning Bolt
4x Young Pyromancer
2 Fire // Ice (APC) 128
SB: 3 Pyroblast
// también acepta comentarios y encabezados`;

// Vista previa del icono. Cae a "?" igual que el dispositivo.
function IconPreview({ tokenKey }) {
  const [i, setI] = useState(0);
  const urls = iconCandidates(tokenKey);
  if (i >= urls.length) return <span className="icon-missing">?</span>;
  return (
    <img
      className="icon-img"
      src={urls[i]}
      alt=""
      draggable={false}
      onError={() => setI(i + 1)}
    />
  );
}

export default function App() {
  const [view, setView] = useState('paste');
  const [deckText, setDeckText] = useState('');
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState(null);
  const [error, setError] = useState(null);
  const [result, setResult] = useState(null); // { parsed, tokens, notFound, suspects }
  const [deckName, setDeckName] = useState('');

  async function analyze() {
    setError(null);
    const parsed = parseDecklist(deckText);
    if (parsed.cards.length === 0) {
      setError('No se reconoció ninguna carta en el texto.');
      return;
    }
    setBusy(true);
    try {
      const r = await deriveTokens(parsed.cards.map((c) => c.name), setProgress);
      setResult({ parsed, ...r });
      setDeckName('');
      setView('review');
    } catch (e) {
      setError(`La consulta a Scryfall falló: ${e.message}. No se generó ningún archivo.`);
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  function download() {
    const content = buildFile({
      deckName,
      cards: result.parsed.cards.map((c) => c.name),
      tokens: result.tokens,
    });
    downloadFile(deckName, content);
  }

  if (view === 'paste') {
    return (
      <div className="app paste">
        <header className="topbar">
          <h1>PaperTokens</h1>
        </header>
        <p className="hint">
          Pega una decklist para generar el archivo de tokens que se copia al
          Kindle. El sideboard cuenta como parte del mazo.
        </p>
        <textarea
          value={deckText}
          onChange={(e) => setDeckText(e.target.value)}
          placeholder={PLACEHOLDER}
          spellCheck={false}
        />
        <button className="primary" onClick={analyze} disabled={busy || !deckText.trim()}>
          {busy ? 'Consultando Scryfall…' : 'Analizar'}
        </button>
        {busy && progress && (
          <div className="status">
            {progress.phase === 'cards' ? 'Buscando cartas' : 'Resolviendo tokens'} — lote{' '}
            {progress.batch}/{progress.total}
          </div>
        )}
        {error && <div className="status error">{error}</div>}
        <p className="hint crosslink">
          ¿Jugar desde el teléfono en vez de generar para el Kindle?{' '}
          <a href="jugar/">Abrir PaperTokens Jugar</a>
        </p>
      </div>
    );
  }

  const { parsed, tokens, notFound, suspects, foundCount } = result;
  const unrecognized = parsed.skipped.filter((s) => s.reason === 'unrecognized');
  const withoutIcon = tokens.filter((t) => !iconKey(t));
  const notPackaged = tokens.filter((t) => iconKey(t) && !isPackaged(iconKey(t)));
  const canDownload = deckName.trim().length > 0 && tokens.length > 0;

  return (
    <div className="app">
      <header className="topbar">
        <button onClick={() => setView('paste')}>←</button>
        <h1>Revisión</h1>
      </header>

      <p className="stats">
        {foundCount} de {parsed.cards.length} cartas encontradas · {tokens.length} tokens.
        El archivo exporta todos; qué entra en juego se elige en el Kindle.
      </p>

      {tokens.length === 0 ? (
        <p className="empty">Ninguna carta del mazo lista tokens en Scryfall.</p>
      ) : (
        <ul className="token-list">
          {tokens.map((t) => {
            const key = iconKey(t);
            return (
              <li key={t.oracleId} className="token-row">
                <span className="row-icon">
                  <IconPreview tokenKey={key} />
                </span>
                <span className="row-main">
                  <span className="row-name">
                    {t.name}
                    {t.isCreature && t.power != null && (
                      <span className="row-pt">
                        {t.power}/{t.toughness}
                      </span>
                    )}
                  </span>
                  <span className="row-sub">{t.typeLine}</span>
                  <span className="row-sub">
                    icono: {key ? <code>{key}</code> : <em>sin clave</em>}
                    {key && !isPackaged(key) && ' · el plugin aún no lo trae'}
                  </span>
                </span>
              </li>
            );
          })}
        </ul>
      )}

      <input
        className="deck-name"
        type="text"
        value={deckName}
        placeholder="Nombre del mazo"
        onChange={(e) => setDeckName(e.target.value)}
      />
      <button className="primary" onClick={download} disabled={!canDownload}>
        Descargar {fileName(deckName)}
      </button>
      <p className="hint">
        Copia el archivo a la carpeta de mazos del plugin en el Kindle.
      </p>

      {(withoutIcon.length > 0 || notPackaged.length > 0) && (
        <div className="section">
          <h2>Iconos por dibujar</h2>
          <ul>
            {withoutIcon.map((t) => (
              <li key={t.oracleId}>
                {t.name}
                <span className="why">sin clave en el mapeo: saldrá “?” en el dispositivo</span>
              </li>
            ))}
            {notPackaged.map((t) => (
              <li key={t.oracleId}>
                {t.name}
                <span className="why">
                  clave <code>{iconKey(t)}</code>, pero el plugin todavía no la empaqueta
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {notFound.length > 0 && (
        <div className="section">
          <h2>No encontradas en Scryfall</h2>
          <ul>
            {notFound.map((n) => (
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

      {suspects.length > 0 && (
        <div className="section">
          <h2>Mencionan crear tokens, sin entrada en all_parts</h2>
          <ul>
            {suspects.map((s) => (
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
