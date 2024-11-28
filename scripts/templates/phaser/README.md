# {{GAME_TITLE}}

{{DESCRIPTION}}

## Getting Started

### Prerequisites

- Node.js (v14+)
- npm or yarn
- Docker (optional)
- Conda (optional)

### Installation

1. Clone the repository:

```bash
git clone <repository-url>
cd {{GAME_NAME}}
```

2. Install dependencies:

```bash
npm install
```

3. Start development server:

```bash
npm run dev
```

4. Build for production:

```bash
npm run build
```

## Development

### Available Scripts

- `npm run dev`: Start development server
- `npm run build`: Build for production
- `npm run test`: Run tests
- `npm run lint`: Check code style
- `npm run format`: Format code

### Docker

Development:

```bash
docker-compose up dev
```

Production:

```bash
docker-compose up prod
```

### Conda Environment

```bash
conda env create -f environment.yml
conda activate {{GAME_NAME}}
```

## License

This project is licensed under the MIT License - see the LICENSE file for details

## Author

{{AUTHOR}} <{{EMAIL}}>
