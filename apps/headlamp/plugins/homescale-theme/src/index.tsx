import {
  AppLogoProps,
  CommonComponents,
  ConfigStore,
  K8s,
  registerAppBarAction,
  registerAppLogo,
  registerAppTheme,
  registerRoute,
  registerSidebarEntry,
} from '@kinvolk/headlamp-plugin/lib';
import React from 'react';
import { LOGO_BANNER_DATA_URI, LOGO_ICON_DATA_URI } from './assets';

// Navy sampled from media/homescale-{icon,transparent,banner}.png in the repo
// root; accent is the requested selection/highlight colour.
const HOMESCALE_NAVY = '#0A0F18';
const HOMESCALE_ACCENT = '#4789CF';

function HomeScaleLogo(props: AppLogoProps) {
  const { logoType, className, sx } = props;

  // The banner already has the icon + "HomeScale" wordmark on the brand navy,
  // which matches navbar.background/sidebar.background below, so it blends
  // in regardless of which base theme (light/dark) is active.
  return (
    <img
      className={className}
      style={{ height: 32, width: 'auto', ...(sx as React.CSSProperties) }}
      src={logoType === 'large' ? LOGO_BANNER_DATA_URI : LOGO_ICON_DATA_URI}
      alt="HomeScale"
    />
  );
}

registerAppLogo(HomeScaleLogo);

const sidebarAndNavbar = {
  sidebar: {
    background: HOMESCALE_NAVY,
    color: '#CBD5E1',
    selectedBackground: HOMESCALE_ACCENT,
    selectedColor: '#FFFFFF',
    actionBackground: '#1E293B',
  },
  navbar: {
    background: HOMESCALE_NAVY,
    color: '#F8FAFC',
  },
  buttonTextTransform: 'none' as const,
  radius: 8,
};

registerAppTheme({
  name: 'homescale',
  base: 'light',
  primary: HOMESCALE_ACCENT,
  secondary: '#F1F5F9',
  ...sidebarAndNavbar,
});

registerAppTheme({
  name: 'homescale-dark',
  base: 'dark',
  primary: HOMESCALE_ACCENT,
  secondary: HOMESCALE_NAVY,
  ...sidebarAndNavbar,
});

// Embeds the real ArgoCD UI for the selected cluster in an iframe, rather
// than proxying through the k8s API: argocd-server's Service always has two
// named ports (http+https, both aliasing the same container port), and an
// unqualified `services/proxy` request to a multi-port Service fails with
// "no endpoints available" regardless of RBAC -- a k8s apiserver limitation
// (see https://github.com/kubernetes/kubernetes/issues/20070), not
// something fixable on our end. Framing works because argocd's
// server.x.frame.options/server.content.security.policy params (see
// apps/argocd/app.yaml) are scoped to allow Headlamp's own origins. First
// login still goes through Entra SAML, whose sign-in page refuses to render
// in an iframe -- the "open in new tab" link is the escape hatch for that.
function ArgoCDEmbed() {
  const cluster = K8s.useCluster();
  const target = cluster ? `https://argocd-server.argocd.${cluster}REDACTED` : null;

  return (
    <>
      <CommonComponents.SectionHeader
        title="ArgoCD"
        actions={
          target
            ? [
                <a key="open" href={target} target="_blank" rel="noopener noreferrer">
                  Open in new tab
                </a>,
              ]
            : null
        }
      />
      <CommonComponents.SectionBox>
        {target ? (
          <iframe
            src={target}
            title="ArgoCD"
            style={{ width: '100%', height: 'calc(100vh - 200px)', border: 'none' }}
          />
        ) : (
          <p>No cluster selected.</p>
        )}
      </CommonComponents.SectionBox>
    </>
  );
}

registerSidebarEntry({
  parent: null,
  name: 'argocd',
  label: 'ArgoCD',
  url: '/argocd',
  icon: 'mdi:git',
});

registerRoute({
  path: '/argocd',
  sidebar: 'argocd',
  name: 'argocd',
  exact: true,
  component: () => <ArgoCDEmbed />,
});

// Headlamp's shipped prometheus plugin defaults to auto-detect, which can't
// find a usable Prometheus Service in this cluster (see apps/metrics'
// prometheus-proxy Service and apps/rbac's observability-viewer for why).
// Point it at prometheus-proxy by default so metrics charts work without
// every user having to configure this by hand in Settings -> Plugins. Only
// seeds the default when unset, so a user's own override is never clobbered.
interface PrometheusPluginConfig {
  autoDetect?: boolean;
  isMetricsEnabled?: boolean;
  address?: string;
  subPath?: string;
}

const PROMETHEUS_PROXY_ADDRESS = 'metrics/prometheus-proxy:9090';

function EnsurePrometheusDefaultConfigured() {
  const cluster = K8s.useCluster();

  React.useEffect(() => {
    if (!cluster) {
      return;
    }
    const configStore = new ConfigStore<Record<string, PrometheusPluginConfig>>('prometheus');
    const current = configStore.get() ?? {};
    const clusterConfig = current[cluster];
    if (!clusterConfig?.address) {
      configStore.update({
        [cluster]: {
          ...clusterConfig,
          autoDetect: false,
          isMetricsEnabled: true,
          address: PROMETHEUS_PROXY_ADDRESS,
        },
      });
    }
  }, [cluster]);

  return null;
}

registerAppBarAction(EnsurePrometheusDefaultConfigured);
