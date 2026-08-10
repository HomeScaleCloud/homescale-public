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

// Links out to the real ArgoCD UI for the selected cluster instead of
// proxying through the k8s API: argocd-server's Service always has two
// named ports (http+https, both aliasing the same container port), and an
// unqualified `services/proxy` request to a multi-port Service fails with
// "no endpoints available" regardless of RBAC -- a k8s apiserver limitation
// (see https://github.com/kubernetes/kubernetes/issues/20070), not
// something fixable on our end.
function ArgoCDRedirect() {
  const cluster = K8s.useCluster();
  const target = cluster ? `https://argocd-server.argocd.${cluster}REDACTED` : null;

  React.useEffect(() => {
    if (target) {
      window.open(target, '_blank', 'noopener,noreferrer');
    }
  }, [target]);

  return (
    <>
      <CommonComponents.SectionHeader title="ArgoCD" />
      <CommonComponents.SectionBox>
        {target ? (
          <p>
            Opened{' '}
            <a href={target} target="_blank" rel="noopener noreferrer">
              {target}
            </a>{' '}
            in a new tab. If it didn't open, click the link.
          </p>
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
  component: () => <ArgoCDRedirect />,
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

// The KubeVirt plugin (headlamp-kubevirt) has its own, separate metrics
// endpoint setting -- it doesn't read the built-in prometheus plugin's
// ConfigStore above. It checks localStorage first, then falls back to a
// per-cluster "headlamp-kubevirt-config" ConfigMap, then gives up with
// "Not configured". Seed the same localStorage key it reads
// (`headlamp-kubevirt-metrics-endpoint`) with the same prometheus-proxy
// Service, expressed as the raw k8s services/proxy subresource path the
// KubeVirt plugin expects (it doesn't do the "namespace/service:port"
// shorthand parsing the built-in plugin does above). Only seeds when unset,
// so a user's own override is never clobbered. Global, not per-cluster,
// since prometheus-proxy is deployed identically on every cluster.
const KUBEVIRT_METRICS_LOCALSTORAGE_KEY = 'headlamp-kubevirt-metrics-endpoint';
const KUBEVIRT_METRICS_ENDPOINT = '/api/v1/namespaces/metrics/services/prometheus-proxy:9090/proxy';

function EnsureKubeVirtMetricsDefaultConfigured() {
  React.useEffect(() => {
    try {
      if (!localStorage.getItem(KUBEVIRT_METRICS_LOCALSTORAGE_KEY)) {
        localStorage.setItem(KUBEVIRT_METRICS_LOCALSTORAGE_KEY, KUBEVIRT_METRICS_ENDPOINT);
      }
    } catch {
      // localStorage unavailable (e.g. private browsing) -- KubeVirt plugin
      // falls back to its own "Not configured" state, nothing more to do.
    }
  }, []);

  return null;
}

registerAppBarAction(EnsureKubeVirtMetricsDefaultConfigured);
