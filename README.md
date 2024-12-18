# winget-pkg-versions

Retrieve latest versions for winget packages.

## Structure

```
manifests/
  a/
    Adobe.Acrobat.Reader.json
    Atlassian.Sourcetree.json
  b/
    Blender.Blender.json
  m/
    Microsoft.Windows.json
  ...
```

## Example

```bash
curl https://raw.githubusercontent.com/hoilc/winget-pkg-versions/main/manifests/a/a/Adobe.Acrobat.Pro.json
```

```json
{
  "id": "Adobe.Acrobat.Pro",
  "version": "24.005.20320"
}
