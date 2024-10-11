/**
 * Proxy.pac function implementation. This is a javascript file that is used by browsers to determine which proxy to use for a given request. 
 * AKA proxy auto-configuration (PAC). or web proxy auto-discovery (WPAD) aka wpad.dat and wpad.da.
 * A very helpful tip for debugging this in firefox (best browser btw) is to hit CTRL+SHIFT+J instead of going to the dev console via F12.
 * The F12 debug console does not show the proxy.pac alert calls, but for some reason ctrl shift J does.
 * Use this with firefox by setting the automatic proxy configuration url to file:///C:/path/to/this/file.pac in the tools->settings scroll down to network settings dialog.
 * @param url The full URL of the request, typically passed in by the browser.
 * @param host The extracted hostname of the request, typically passed in by the browser.
 * @returns "DIRECT" or a specified proxy IAW the proxy auto-configuration (PAC) specification.
 * @author OperativeThunny
 * @license Affero General Public License v3.0 (AGPL-3.0) https://opensource.org/licenses/AGPL-3.0 / https://www.gnu.org/licenses/agpl-3.0.en.html
 */
// If you try to declare the function in the hipster newschool way of javascript using the const keyword,
// then it will not work because at the site of invocation,
// the function will be undefined because of javascript hoisting differences between var, function, const, and let keywords.
function FindProxyForURL(url, host) {
    const myDnsDomainIs = (host, domain) => {
        return (host.length >= domain.length &&
                host.substring(host.length - domain.length) == domain);
    }

    const proxiedEntities = {
        "SOCKS5 127.0.0.1:5150": ["youtube.com", "google.com", "www.youtube.com", "ggpht.com", "ytimg.com", "gstatic.com", "googleapis.com", "googlevideo.com"],
        "SOCKS5 127.0.0.1:5152": [".doesnotexist.example.com"]
    }

    for (const proxy in proxiedEntities) {
        for (const domain of proxiedEntities[proxy]) { // if this was an for..in instead of for..of, then domain would be the numerical index in the array of domains for the proxy insead of the value of each element in the array.
            if (dnsDomainIs(host, domain)) {
                alert(["Proxying request", proxy, domain])
                return proxy
            }
        }
    }

    alert(["DIRECT", url, host])
    return "DIRECT"
}
