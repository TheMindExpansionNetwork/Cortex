import { useEffect, useState } from 'react';
import { tr } from '../lib/i18n';
import { Btn, Dialog } from './ui';

/**
 * Browser mode only (the app window could not start, or the person asked for `--browser`): closing the tab does not stop Cortex or
 * its engine, so the menu has "Quit Cortex". The host refuses the request in the app window, where closing the window quits.
 */
export function QuitCortexDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [state, setState] = useState<'ask' | 'stopping' | 'stopped' | 'failed'>('ask');
  useEffect(() => { if (open) setState('ask'); }, [open]);
  async function quit() {
    setState('stopping');
    try {
      // the header is what a web page on another site cannot send; the host also refuses any request that does not come from this computer
      const response = await fetch('/api/app/quit', { method: 'POST', headers: { 'x-cortex-client': 'ui' } });
      setState(response.ok ? 'stopped' : 'failed');
    } catch { setState('failed'); }
  }
  const stopped = state === 'stopped';
  return <Dialog open={open} compact title={tr(stopped ? "Cortex has stopped" : "Quit Cortex?")} onClose={state === 'stopping' ? () => {} : onClose}
    actions={stopped ? undefined : <><Btn onClick={onClose} disabled={state === 'stopping'}>{tr("Cancel")}</Btn><Btn variant="primary" disabled={state === 'stopping'} onClick={() => void quit()}>{tr(state === 'stopping' ? "Quitting…" : "Quit Cortex")}</Btn></>}>
    <p className="small" role="status">{tr(stopped
      ? "Cortex has stopped. You can close this tab. To use it again, start Cortex from its icon."
      : state === 'failed'
        ? "Cortex could not be stopped from here. Run the app with --quit in a terminal, or try again."
        : "This stops the model and ends Cortex. Your chats and files stay as they are. Closing the browser tab alone would leave Cortex running.")}</p>
  </Dialog>;
}
