import Foundation
import ApusCore

/// Generates a self-contained HTML page with an interactive Cytoscape.js graph explorer.
public struct WebExplorerTemplate: Sendable {

    public init() {}

    /// Generate a complete HTML page that fetches graph data from /api/graph.
    public func generateHTML(snapshot: GraphSnapshot, projectName: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(projectName)) — Apus Graph Explorer</title>
            <script src="https://unpkg.com/cytoscape@3.30.4/dist/cytoscape.min.js"></script>
            <script src="https://unpkg.com/layout-base@2.0.1/layout-base.js"></script>
            <script src="https://unpkg.com/cose-base@2.2.0/cose-base.js"></script>
            <script src="https://unpkg.com/cytoscape-cose-bilkent@4.1.0/cytoscape-cose-bilkent.js"></script>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; display: flex; height: 100vh; background: #1a1a2e; color: #e0e0e0; }
                #sidebar { width: 280px; padding: 16px; overflow-y: auto; background: #16213e; border-right: 1px solid #333; flex-shrink: 0; }
                #sidebar h1 { font-size: 18px; margin-bottom: 12px; color: #fff; }
                #sidebar h2 { font-size: 13px; margin: 12px 0 6px; color: #999; text-transform: uppercase; letter-spacing: 1px; }
                #search { width: 100%; padding: 8px; border: 1px solid #444; border-radius: 4px; background: #0f3460; color: #fff; font-size: 13px; margin-bottom: 8px; }
                #search::placeholder { color: #777; }
                .filter-group { margin-bottom: 8px; }
                .filter-group label { display: block; font-size: 12px; padding: 2px 0; cursor: pointer; }
                .filter-group input[type="checkbox"] { margin-right: 6px; }
                #info { margin-top: 12px; padding: 10px; background: #0f3460; border-radius: 4px; font-size: 12px; line-height: 1.6; min-height: 80px; }
                #info .label { color: #999; }
                #info .value { color: #fff; }
                .toolbar { display: flex; gap: 6px; margin-bottom: 8px; flex-wrap: wrap; }
                .toolbar button { padding: 4px 10px; border: 1px solid #444; border-radius: 4px; background: #0f3460; color: #e0e0e0; cursor: pointer; font-size: 12px; }
                .toolbar button:hover { background: #1a4a8a; }
                #cy { flex: 1; background: #1a1a2e; }
                .stats { font-size: 11px; color: #666; margin-top: 8px; }
            </style>
        </head>
        <body>
            <div id="sidebar">
                <h1>\(escapeHTML(projectName))</h1>
                <input type="text" id="search" placeholder="Search nodes..." autocomplete="off">

                <h2>Layout</h2>
                <div class="toolbar">
                    <button onclick="setLayout('cose-bilkent')">cose-bilkent</button>
                    <button onclick="setLayout('circle')">circle</button>
                    <button onclick="setLayout('grid')">grid</button>
                    <button onclick="setLayout('breadthfirst')">tree</button>
                </div>

                <div class="toolbar">
                    <button onclick="cy.fit()">Fit</button>
                    <button onclick="exportPNG()">Export PNG</button>
                </div>

                <h2>Filter by Target</h2>
                <div class="filter-group" id="target-filters"></div>

                <h2>Filter by Kind</h2>
                <div class="filter-group" id="kind-filters"></div>

                <h2>Node Info</h2>
                <div id="info">Click a node to inspect it.</div>

                <div class="stats" id="stats"></div>
            </div>
            <div id="cy"></div>

            <script>
            // Register cose-bilkent layout plugin
            if (typeof cytoscapeCoseBilkent !== 'undefined') {
                cytoscapeCoseBilkent(cytoscape);
            }

            let cy;

            function setLayout(name) {
                if (!cy) return;
                const opts = { name: name, animate: false };
                if (name === 'cose-bilkent') opts.nodeDimensionsIncludeLabels = true;
                cy.layout(opts).run();
            }

            function exportPNG() {
                if (!cy) return;
                const a = document.createElement('a');
                a.href = cy.png({ full: true, scale: 2, bg: '#1a1a2e' });
                a.download = '\(escapeHTML(projectName))-graph.png';
                a.click();
            }

            function updateStats() {
                if (!cy) return;
                const visible = cy.nodes().not('.hidden');
                const visEdges = cy.edges().not('.hidden');
                document.getElementById('stats').textContent = `Showing ${visible.length} nodes, ${visEdges.length} edges`;
            }

            // Fetch graph data from API endpoint
            document.getElementById('info').innerHTML = 'Loading graph data...';

            fetch('/api/graph')
                .then(r => r.json())
                .then(graphData => {
                    cy = cytoscape({
                        container: document.getElementById('cy'),
                        elements: graphData.elements,
                        style: [
                            { selector: 'node', style: {
                                'label': 'data(label)',
                                'background-color': 'data(color)',
                                'shape': 'data(shape)',
                                'font-size': '10px',
                                'color': '#ccc',
                                'text-valign': 'bottom',
                                'text-margin-y': 5,
                                'width': 30,
                                'height': 30,
                                'border-width': 1,
                                'border-color': '#555'
                            }},
                            { selector: 'edge', style: {
                                'label': 'data(label)',
                                'font-size': '8px',
                                'color': '#666',
                                'line-color': '#555',
                                'target-arrow-color': '#555',
                                'target-arrow-shape': 'triangle',
                                'curve-style': 'bezier',
                                'width': 1
                            }},
                            { selector: 'node:selected', style: {
                                'border-color': '#e74c3c',
                                'border-width': 3
                            }},
                            { selector: '.highlighted', style: {
                                'border-color': '#f39c12',
                                'border-width': 2,
                                'line-color': '#f39c12',
                                'target-arrow-color': '#f39c12',
                                'width': 2
                            }},
                            { selector: '.faded', style: { 'opacity': 0.15 } },
                            { selector: '.hidden', style: { 'display': 'none' } }
                        ],
                        layout: { name: 'cose-bilkent', animate: false, nodeDimensionsIncludeLabels: true }
                    });

                    // Build filter checkboxes
                    const targets = new Set();
                    const kinds = new Set();
                    cy.nodes().forEach(n => {
                        if (n.data('targetName')) targets.add(n.data('targetName'));
                        if (n.data('kind')) kinds.add(n.data('kind'));
                    });

                    function buildFilters(containerId, values) {
                        const el = document.getElementById(containerId);
                        [...values].sort().forEach(v => {
                            const lbl = document.createElement('label');
                            const cb = document.createElement('input');
                            cb.type = 'checkbox'; cb.checked = true; cb.value = v;
                            cb.addEventListener('change', applyFilters);
                            lbl.appendChild(cb);
                            lbl.appendChild(document.createTextNode(v));
                            el.appendChild(lbl);
                        });
                    }
                    buildFilters('target-filters', targets);
                    buildFilters('kind-filters', kinds);

                    function applyFilters() {
                        const checkedTargets = new Set([...document.querySelectorAll('#target-filters input:checked')].map(c => c.value));
                        const checkedKinds = new Set([...document.querySelectorAll('#kind-filters input:checked')].map(c => c.value));
                        cy.nodes().forEach(n => {
                            const t = n.data('targetName') || '';
                            const k = n.data('kind') || '';
                            const show = (checkedTargets.size === 0 || !t || checkedTargets.has(t)) && (checkedKinds.size === 0 || !k || checkedKinds.has(k));
                            show ? n.removeClass('hidden') : n.addClass('hidden');
                        });
                        cy.edges().forEach(e => {
                            (e.source().hasClass('hidden') || e.target().hasClass('hidden')) ? e.addClass('hidden') : e.removeClass('hidden');
                        });
                        updateStats();
                    }

                    // Search
                    document.getElementById('search').addEventListener('input', function() {
                        const q = this.value.toLowerCase();
                        cy.elements().removeClass('faded highlighted');
                        if (!q) return;
                        cy.nodes().forEach(n => {
                            if ((n.data('label') || '').toLowerCase().includes(q)) {
                                n.addClass('highlighted');
                            } else {
                                n.addClass('faded');
                            }
                        });
                        cy.edges().forEach(e => {
                            (e.source().hasClass('faded') && e.target().hasClass('faded')) ? e.addClass('faded') : 0;
                        });
                    });

                    // Click to inspect
                    cy.on('tap', 'node', function(evt) {
                        const d = evt.target.data();
                        document.getElementById('info').innerHTML = `
                            <div><span class="label">Name:</span> <span class="value">${d.label || ''}</span></div>
                            <div><span class="label">Kind:</span> <span class="value">${d.kind || ''}</span></div>
                            <div><span class="label">Access:</span> <span class="value">${d.accessLevel || 'n/a'}</span></div>
                            <div><span class="label">Target:</span> <span class="value">${d.targetName || 'n/a'}</span></div>
                            <div><span class="label">ID:</span> <span class="value" style="word-break:break-all;font-size:10px">${d.id || ''}</span></div>
                        `;
                        cy.elements().removeClass('highlighted faded');
                        const neighborhood = evt.target.neighborhood().add(evt.target);
                        neighborhood.addClass('highlighted');
                        cy.elements().not(neighborhood).addClass('faded');
                    });

                    cy.on('tap', function(evt) {
                        if (evt.target === cy) {
                            cy.elements().removeClass('highlighted faded');
                            document.getElementById('info').innerHTML = 'Click a node to inspect it.';
                        }
                    });

                    document.getElementById('info').innerHTML = 'Click a node to inspect it.';
                    updateStats();
                })
                .catch(err => {
                    document.getElementById('info').innerHTML = `<span style="color:#e74c3c">Failed to load graph: ${err.message}</span>`;
                });
            </script>
        </body>
        </html>
        """
    }

    private func escapeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
