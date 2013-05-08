#!/bin/bash

#/ Usage:  generate-xmldsig.sh <c14n-executable>
#/
#/ Generates a sample XMLDSig document, ie. a very simple XML sub-document signed
#/ with a fake key generated by this script.  The script also generates
#/ a self-signed certificate associated with the private key and includes it in the
#/ output.
#/
#/ The script requires <c14n-executable> which can produced a canonicalised XML
#/ sub-document given the XML file (on its standard input) and a XPath expression
#/ specifying the root node of the canonicalised sub-document.
#/
#/ Examples:
#/  ./generate-xmldsig.sh /tmp/c14n-exe > /tmp/sample.xml

function usage() { grep '^#/' "$0" | cut -c 4-; }

xmldsig_c14n_exe=$1

[ -z "$xmldsig_c14n_exe" ] && {
  echo "Missing argument:  an executable to get C14N XML sub-document" >&2
  echo
  usage
  exit 1
}

template='
<Signature xmlns="http://www.w3.org/2000/09/xmldsig#" Id="PackageSignature">
  <SignedInfo>
    <CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/>
    <SignatureMethod Algorithm="http://www.w3.org/TR/xmldsig-core#rsa-sha1"/>
    <Reference URI="#PackageContents">
      <Transforms>
        <Transform Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315"/>
      </Transforms>
      <DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
      <DigestValue>%s</DigestValue>
    </Reference>
  </SignedInfo>
  <SignatureValue Id="PackageSignatureValue">%s</SignatureValue>
  <KeyInfo>
    <X509Data>
      <X509Certificate>%s</X509Certificate>
    </X509Data>
  </KeyInfo>
  <Object>
    <Manifest Id="PackageContents"></Manifest>
  </Object>
</Signature>
'

function gen_xml() {
  local digest="$1"
  local signature="$2"
  local certificate="$3"

  printf "$template" "$digest" "$signature" "$certificate"
}

function sign() {
  local msg="$1"
  local key="$2"
  local pass="$3"

  echo -n "$msg" | \
  openssl dgst -binary -sha1 -sign "$key" -passin pass:"$pass" | \
  openssl base64
}

# scratch directory
tmpdir=$(mktemp -d)

# Don't care about the password as this is all fake material for testing
pass="none"

# private key
key_priv="${tmpdir}/test-key-priv.pem"

# associated certificate
cert="${tmpdir}/test-cert.pem"

# generate private key and certificate with public key
openssl req -x509 -newkey rsa:2048 \
    -keyout "${key_priv}" -subj "/CN=FakeSigner" \
    -passout pass:"${pass}" -out "${cert}" &>/dev/null

manifest_xpath="/default:Signature/default:Object/default:Manifest"
si_xpath="/default:Signature/default:SignedInfo"

canonicalised_manifest=$(
  $xmldsig_c14n_exe $manifest_xpath <<< $template
)
manifest_digest=$(
  echo -n $canonicalised_manifest | \
  openssl dgst -sha256 -binary | \
  openssl base64
)

# SignatureInfo
canonicalised_si=$(
  gen_xml "$manifest_digest" "" "" | $xmldsig_c14n_exe "$si_xpath"
)

signature=$(sign "$canonicalised_si" "$key_priv" "$pass")
cert_blob=$(grep -v "CERT" "$cert")

# remove the scratch directory
rm -rf "$tmpdir"

gen_xml "$manifest_digest" "$signature" "$cert_blob"